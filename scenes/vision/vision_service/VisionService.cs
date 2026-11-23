using Godot;
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;

using DrunkenVikings.Vision;

/// <summary>
/// Capture the webcam, follow the players' body poses on a background thread,
/// and measure the signals of the rowing (see <see cref="RowingSignals"/>).
/// </summary>
/// <remarks>
/// <para>
/// The pose thread runs <see cref="PoseFollower"/> back to back: RTMPose-t
/// follows each player on every frame, and RTMO finds them at the start or
/// when they were lost. The main thread only copies a camera frame when the
/// thread asks for one, so that we never queue frames (and latency) nor copy
/// frames nobody processes. The thread publishes immutable snapshots
/// (<see cref="VisionSnapshot"/>), which the main thread turns into the
/// signals in <see cref="_Process"/>.
/// </para>
/// <para>
/// One or two players row together (see <see cref="SetPlayerCount"/>). With
/// two, each plays in their own half of the camera picture: the player on the
/// left of the mirrored picture is player 0 (see <see cref="PlayerSplit"/>).
/// The game (GDScript) uses only the plain getters, which take the player.
/// </para>
/// </remarks>
public partial class VisionService : Node
{
    public enum ServiceStatus
    {
        Disabled,
        SearchingCamera,
        LoadingModels,
        Running,
        NoCamera,
        ModelsMissing,
        Failed,
    }

    public const string RtmoModelPath = "res://scenes/vision/rtmo/model/rtmo_t_body7_416x416.onnx";

    public const string RtmPoseModelPath = "res://scenes/vision/rtmpose/model/rtmpose_t_body7_256x192.onnx";

    public const string HandModelPath = "res://scenes/vision/yolox/model/yolox_n_body_head_hand_Nx3xHxW.onnx";

    /// <summary>Use only the key points of at least this score for the signals.</summary>
    public const float KeypointThreshold = 0.3f;

    /// <summary>How long to wait for the camera feeds to appear, in seconds.</summary>
    private const double _cameraSearchTimeout = 5.0;

    /// <summary>Once a feed appeared, how long to wait for more, in seconds.</summary>
    private const double _graceAfterFirstFeed = 1.0;

    /// <summary>Set to false before the node enters the tree to run without the camera.</summary>
    [Export]
    public bool UseCamera = true;

    /// <summary>Which of the compatible cameras to use.</summary>
    [Export]
    public int CameraIndex = 0;

    /// <summary>The threads of RTMO.</summary>
    [Export]
    public int Threads = 2;

    public ServiceStatus Status { get; private set; } = ServiceStatus.Disabled;

    public string StatusMessage { get; private set; } = "";

    public CameraTexture? CameraTexture { get; private set; }

    /// <summary>How many players row (1 or 2).</summary>
    public int PlayerCount { get; private set; } = 1;

    /// <summary>The unit of each player.</summary>
    private readonly BodyScale[] _scales = { new(), new() };

    /// <summary>The signals of each player on their latest pose.</summary>
    private readonly RowingSignals[] _signals = { RowingSignals.Unknown, RowingSignals.Unknown };

    /// <summary>The strokes and the steering of each player.</summary>
    private readonly RowingMeter[] _meters = { new(), new() };

    /// <summary>When each player was seen the last time.</summary>
    private readonly double[] _seenAt = { double.NegativeInfinity, double.NegativeInfinity };

    /// <summary>The recording of the vision (see dev/rowing/), or null.</summary>
    private VisionRecorder? _recorder;

    /// <summary>How many poses a second came lately (smoothed).</summary>
    private double _poseRate;

    /// <summary>The camera frames to save as pictures while recording with frames, or null.</summary>
    private BlockingCollection<(byte[] Rgb, int Width, int Height, string Path)>? _frameQueue;
    private Thread? _frameWriter;
    private string _framesDirectory = "";
    private int _framesSaved;

    private readonly Stopwatch _clock = Stopwatch.StartNew();

    /// <summary>Seconds on the clock of the frame timestamps.</summary>
    public double Now => _clock.Elapsed.TotalSeconds;

    private VisionSnapshot? _latest;
    private VisionSnapshot? _consumed;

    /// <summary>The latest poses, or null before the first ones.</summary>
    public VisionSnapshot? Latest => Volatile.Read(ref _latest);

    private CameraFeed? _feed;

    /// <summary>The camera extension on Windows (see <see cref="StartCameraExtension"/>), or null.</summary>
    private GodotObject? _cameraExtension;

    /// <summary>
    /// Why there may be no camera: "unsupported" (on Windows without the camera
    /// extension), "denied" (Windows does not allow the camera), or "" otherwise.
    /// </summary>
    private string _noCameraReason = "";

    /// <summary>
    /// The chroma plane of a feed which delivers its frames as two planes (Y and
    /// CbCr, e.g., on macOS); <see cref="CameraTexture"/> then holds the Y plane.
    /// </summary>
    private CameraTexture? _cbcrTexture;

    /// <summary>The frames of a two-plane feed converted to RGB, for the preview.</summary>
    private ImageTexture? _ycbcrPreview;

    /// <summary>Try to activate the feed again at this time, see <see cref="RetryActivation"/>.</summary>
    private double _nextActivationAttempt = double.NaN;

    /// <summary>Try to activate an inactive feed again every this many seconds.</summary>
    private const double _activationRetryPeriod = 3.0;

    /// <summary>Convert the two-plane frames down to at most this width.</summary>
    private const int _maxYcbcrWidth = 640;

    private double _searchStarted = double.NaN;
    private double _firstFeedAt = double.NaN;

    /// <summary>Whether we kept the full frame rate of the camera once it streamed.</summary>
    private bool _fullFrameRateKept;

    /// <summary>Hand the camera frames over to the pose thread.</summary>
    private sealed class FrameSlot
    {
        public volatile bool Requested;
        public readonly AutoResetEvent Ready = new(false);
        private readonly object _lock = new();
        private Frame? _pending;

        public void Put(Frame frame)
        {
            lock (_lock)
            {
                _pending = frame;
            }

            Requested = false;
            Ready.Set();
        }

        public Frame? Take()
        {
            lock (_lock)
            {
                var frame = _pending;
                _pending = null;
                return frame;
            }
        }
    }

    private Thread? _poseThread;
    private Thread? _handThread;
    private volatile bool _running;

    /// <summary>Whether the hand detector runs (only while a screen shows the hand cursor).</summary>
    private volatile bool _handTracking;

    private readonly FrameSlot _handSlot = new();

    /// <summary>The hands which YOLOX found last: the time, the size of the frame and the boxes.</summary>
    private sealed class HandSnapshot
    {
        public double Timestamp { get; init; }
        public int Width { get; init; }
        public int Height { get; init; }
        public IReadOnlyList<BoundingBox> Hands { get; init; } = Array.Empty<BoundingBox>();
    }

    private HandSnapshot? _latestHands;

    /// <summary>Whether we shut down (see <see cref="Shutdown"/>): no more frames are taken.</summary>
    private bool _shutDown;
    private volatile int _threadPlayerCount = 1;
    private readonly FrameSlot _poseSlot = new();

    public override void _Ready()
    {
        if (!UseCamera)
        {
            SetStatus(ServiceStatus.Disabled, "The camera is switched off.");
            return;
        }

        foreach (string path in new[] { RtmoModelPath, RtmPoseModelPath })
        {
            if (!FileAccess.FileExists(path))
            {
                SetStatus(ServiceStatus.ModelsMissing, $"The pose model {path} is missing; run `git lfs pull`.");
                return;
            }
        }

        CameraServer.MonitoringFeeds = true;
        if (OS.GetName() == "Windows")
        {
            StartCameraExtension();
        }

        _searchStarted = Now;
        SetStatus(ServiceStatus.SearchingCamera, "Looking for a camera...");
    }

    public override void _Process(double delta)
    {
        double now = Now;

        if (Status == ServiceStatus.SearchingCamera)
        {
            SearchCamera(now);
        }

        RetryActivation(now);

        var snapshot = Latest;
        if (snapshot != null && !ReferenceEquals(snapshot, _consumed))
        {
            if (_consumed != null && snapshot.Timestamp > _consumed.Timestamp)
            {
                double rate = 1.0 / (snapshot.Timestamp - _consumed.Timestamp);
                _poseRate = _poseRate <= 0.0 ? rate : _poseRate * 0.9 + rate * 0.1;
            }

            _consumed = snapshot;
            Consume(snapshot);
        }
    }

    private void Consume(VisionSnapshot snapshot)
    {
        int count = Math.Min(snapshot.Players.Count, PlayerSplit.MaxPlayers);
        var signals = new RowingSignals[count];
        for (int i = 0; i < count; i++)
        {
            var pose = snapshot.Players[i];
            float unit = _scales[i].Observe(snapshot.Timestamp, pose, KeypointThreshold);
            _signals[i] = RowingSignals.Measure(pose, unit, snapshot.Height, KeypointThreshold);
            signals[i] = _signals[i];
            var head = pose?.Head(KeypointThreshold);
            _meters[i].Observe(
                snapshot.Timestamp, head?.X ?? float.NaN, head?.Y ?? float.NaN, unit);
            if (pose != null)
            {
                _seenAt[i] = snapshot.Timestamp;
            }
        }

        _recorder?.RecordPose(snapshot, signals);
    }

    // ---------------------------------------------------------------------
    // The getters for GDScript
    // ---------------------------------------------------------------------

    public string GetStatus() => Status.ToString();

    public string GetStatusMessage() => StatusMessage;

    public bool IsRunning() => Status == ServiceStatus.Running;

    /// <summary>Why there may be no camera, see <see cref="_noCameraReason"/>.</summary>
    public string GetNoCameraReason() => _noCameraReason;

    public Texture2D? GetCameraTexture() => _ycbcrPreview ?? (Texture2D?)CameraTexture;

    /// <summary>The size of the camera picture in pixels, or (640, 480) before the first frame.</summary>
    public Vector2 GetPictureSize()
    {
        var pose = Latest;
        return pose != null ? new Vector2(pose.Width, pose.Height) : new Vector2(640, 480);
    }

    /// <summary>Set how many players row (1 or 2); each gets their half of the picture with two.</summary>
    public void SetPlayerCount(int count)
    {
        int clamped = Math.Clamp(count, 1, PlayerSplit.MaxPlayers);
        if (clamped == PlayerCount)
        {
            return;
        }

        PlayerCount = clamped;
        _threadPlayerCount = clamped;
        ResetPlayers();
    }

    public int GetPlayerCount() => PlayerCount;

    private static int Index(int player) => Math.Clamp(player, 0, PlayerSplit.MaxPlayers - 1);

    /// <summary>Whether the player was seen in the last half second.</summary>
    public bool HasPlayer(int player) => Now - _seenAt[Index(player)] < 0.5;

    private Pose? PoseOf(int player)
    {
        var snapshot = Latest;
        int i = Index(player);
        return snapshot != null && i < snapshot.Players.Count ? snapshot.Players[i] : null;
    }

    /// <summary>The player's 17 key points in the mirrored picture, normalized; empty without them.</summary>
    public Vector2[] GetKeypoints(int player)
    {
        var snapshot = Latest;
        var pose = PoseOf(player);
        if (snapshot == null || pose == null || Now - snapshot.Timestamp > 1.0)
        {
            return Array.Empty<Vector2>();
        }

        var points = new Vector2[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            var keypoint = pose.Keypoints[i];
            points[i] = new Vector2(1f - keypoint.X / snapshot.Width, keypoint.Y / snapshot.Height);
        }

        return points;
    }

    /// <summary>The scores of the key points of <see cref="GetKeypoints"/>.</summary>
    public float[] GetKeypointScores(int player)
    {
        var pose = PoseOf(player);
        if (pose == null)
        {
            return Array.Empty<float>();
        }

        var scores = new float[Pose.KeypointCount];
        for (int i = 0; i < Pose.KeypointCount; i++)
        {
            scores[i] = pose.Keypoints[i].Score;
        }

        return scores;
    }

    /// <summary>
    /// Run the hand detector (for the hand cursor of the screens) or stop it,
    /// so that it takes the processor only while a screen needs it.
    /// </summary>
    public void SetHandTracking(bool on) => _handTracking = on;

    /// <summary>
    /// The hands which the hand detector found lately (of all the players), as
    /// their centers in the mirrored picture, normalized; empty if none were
    /// found in the last 0.3 s, or the detector does not run.
    /// </summary>
    public Vector2[] GetHands()
    {
        var snapshot = Volatile.Read(ref _latestHands);
        if (snapshot == null || !_handTracking || Now - snapshot.Timestamp > 0.3)
        {
            return Array.Empty<Vector2>();
        }

        var hands = new Vector2[snapshot.Hands.Count];
        for (int i = 0; i < hands.Length; i++)
        {
            var box = snapshot.Hands[i];
            hands[i] = new Vector2(1f - box.CenterX / snapshot.Width, box.CenterY / snapshot.Height);
        }

        return hands;
    }

    /// <summary>Which model found the latest pose of the player: "Rtmo", "RtmPose" or "None".</summary>
    public string GetPoseSource(int player)
    {
        var snapshot = Latest;
        int i = Index(player);
        return snapshot != null && i < snapshot.Sources.Count ? snapshot.Sources[i].ToString() : "None";
    }

    /// <summary>The names of the signals, in the order of <see cref="GetSignals"/>.</summary>
    public string[] GetSignalNames() => RowingSignals.Names;

    /// <summary>The signals of the player on their latest pose (see <see cref="RowingSignals"/>); NaN where unknown.</summary>
    public float[] GetSignals(int player) => _signals[Index(player)].ToArray();

    /// <summary>How many strokes the player rowed so far (see <see cref="RowingMeter"/>).</summary>
    public int GetStrokes(int player) => _meters[Index(player)].Strokes;

    /// <summary>How deep the last stroke of the player was, in units of the player (about 0.5 to 1).</summary>
    public float GetLastStrokeDepth(int player) => _meters[Index(player)].LastStrokeDepth;

    /// <summary>The steering of the player in [-1, 1], positive to the player's right.</summary>
    public float GetSteer(int player) => _meters[Index(player)].Steer;

    /// <summary>
    /// How far the player is through the stroke now (0 reaching forward, 1
    /// leaning back; see <see cref="RowingMeter.Pull"/>), or -1 while they do not row.
    /// </summary>
    public float GetPull(int player)
    {
        float pull = _meters[Index(player)].Pull;
        return float.IsNaN(pull) ? -1f : pull;
    }

    /// <summary>How far the head of the player is to their right of home, in units.</summary>
    public float GetShift(int player) => _meters[Index(player)].Shift;

    /// <summary>How long the latest poses took, in milliseconds.</summary>
    public double GetInferenceMs() => Latest?.InferenceMs ?? 0.0;

    /// <summary>How many times a second the poses come now.</summary>
    public double GetPoseRate() => _poseRate;

    /// <summary>Forget the players, e.g., when they change.</summary>
    public void ResetPlayers()
    {
        for (int i = 0; i < PlayerSplit.MaxPlayers; i++)
        {
            _scales[i].Reset();
            _meters[i].Reset();
            _signals[i] = RowingSignals.Unknown;
            _seenAt[i] = double.NegativeInfinity;
        }
    }

    // ---------------------------------------------------------------------
    // The recording
    // ---------------------------------------------------------------------

    /// <summary>
    /// Record what the vision measures into <paramref name="path"/> (as JSON
    /// lines, see <see cref="VisionRecorder"/>); with <paramref name="frames"/>,
    /// also save every camera frame as a picture into
    /// <c>&lt;recording&gt;.frames/</c> (00001.jpg, ...). Return whether it started.
    /// </summary>
    /// <remarks>
    /// The pictures are only for developing the vision (see
    /// dev/rowing/record_rowing.gd, <c>--frames</c>): the game never saves them.
    /// </remarks>
    public bool StartRecording(string path, bool frames, string note)
    {
        StopRecording();
        try
        {
            string global = ProjectSettings.GlobalizePath(path);
            _recorder = new VisionRecorder(global);
            var size = GetPictureSize();
            _recorder.RecordStart(Now, (int)size.X, (int)size.Y, PlayerCount, note);
            if (frames)
            {
                StartFrameWriter(System.IO.Path.ChangeExtension(global, null) + ".frames");
            }

            return true;
        }
        catch (Exception exception)
        {
            GD.PushError($"Could not record into {path}: {exception.Message}");
            _recorder = null;
            return false;
        }
    }

    private void StartFrameWriter(string directory)
    {
        System.IO.Directory.CreateDirectory(directory);
        _framesDirectory = directory;
        _framesSaved = 0;

        // NOTE (mristin):
        // Encoding a picture takes a few milliseconds, so a thread of its own
        // does it; if it falls behind, we rather drop frames than the vision.
        var queue = new BlockingCollection<(byte[] Rgb, int Width, int Height, string Path)>(boundedCapacity: 90);
        _frameQueue = queue;
        _frameWriter = new Thread(() =>
        {
            foreach (var (rgb, width, height, file) in queue.GetConsumingEnumerable())
            {
                var image = Image.CreateFromData(width, height, false, Image.Format.Rgb8, rgb);
                image.SaveJpg(file, 0.9f);
            }
        })
        {
            Name = "Frame writer",
            IsBackground = true,
            Priority = ThreadPriority.BelowNormal,
        };
        _frameWriter.Start();
    }

    /// <summary>Save the camera frame as a picture, if we record with frames.</summary>
    private void SaveFrame(Frame frame)
    {
        if (_frameQueue == null || _recorder == null)
        {
            return;
        }

        int index = _framesSaved + 1;
        string file = $"{_framesDirectory}/{index:00000}.jpg";
        if (_frameQueue.TryAdd((frame.Rgb, frame.Width, frame.Height, file)))
        {
            _framesSaved = index;
            _recorder.RecordFrame(frame.Timestamp, index);
        }
    }

    /// <summary>Label what the player is asked to do from now on in the recording.</summary>
    public void SetRecordingLabel(string label)
    {
        if (_recorder != null)
        {
            _recorder.Label = label;
        }
    }

    /// <summary>Mark this moment in the recording, e.g., when the player was called to pull.</summary>
    public void MarkRecording(string name) => _recorder?.RecordMark(Now, name);

    /// <summary>Stop recording, and return how many lines were recorded.</summary>
    public int StopRecording()
    {
        if (_recorder == null)
        {
            return 0;
        }

        if (_frameQueue != null)
        {
            _frameQueue.CompleteAdding();
            _frameWriter?.Join();
            _frameQueue.Dispose();
            _frameQueue = null;
            _frameWriter = null;
        }

        int lines = _recorder.Lines;
        _recorder.Dispose();
        _recorder = null;
        return lines;
    }

    // ---------------------------------------------------------------------
    // The camera
    // ---------------------------------------------------------------------

    /// <summary>
    /// Load CameraServerExtension, which provides the camera feeds on Windows,
    /// where Godot 4.6 implements no camera (see
    /// addons/CameraServerExtension/CameraServerExtension.gdextension).
    /// </summary>
    /// <remarks>
    /// The extension must be created after <see cref="CameraServer.MonitoringFeeds"/>
    /// is set, and must live as long as its feeds are in use.
    /// </remarks>
    private void StartCameraExtension()
    {
        // NOTE (mristin):
        // The packaging puts the extension next to the executable; in the
        // editor, it stays in the project.
        string directory = OS.HasFeature("editor")
            ? ProjectSettings.GlobalizePath("res://addons/CameraServerExtension")
            : OS.GetExecutablePath().GetBaseDir();
        string path = directory.PathJoin("CameraServerExtension.gdextension");
        if (!System.IO.File.Exists(path))
        {
            GD.PushWarning($"The camera extension {path} is missing; there is no camera on Windows without it.");
            _noCameraReason = "unsupported";
            return;
        }

        var status = GDExtensionManager.LoadExtension(path);
        if (status != GDExtensionManager.LoadStatus.Ok && status != GDExtensionManager.LoadStatus.AlreadyLoaded)
        {
            GD.PushWarning($"The camera extension {path} did not load: {status}.");
            _noCameraReason = "unsupported";
            return;
        }

        if (!ClassDB.ClassExists("CameraServerExtension"))
        {
            GD.PushWarning($"The camera extension {path} loaded, but provides no CameraServerExtension.");
            _noCameraReason = "unsupported";
            return;
        }

        _cameraExtension = ClassDB.Instantiate("CameraServerExtension").AsGodotObject();
        GD.Print($"Loaded the camera extension {path}.");
        if (_cameraExtension != null && !_cameraExtension.Call("permission_granted").AsBool())
        {
            _noCameraReason = "denied";
        }
    }

    /// <summary>
    /// Whether a feed comes from CameraServerExtension, whose formats must be
    /// called by name: the methods of <see cref="CameraFeed"/> do not reach them.
    /// </summary>
    private static bool IsExtensionFeed(CameraFeed feed) => feed.GetClass() == "CameraFeedExtension";

    private static Godot.Collections.Array GetFormats(CameraFeed feed) =>
        IsExtensionFeed(feed) ? feed.Call("get_formats").AsGodotArray() : feed.GetFormats();

    private static void SetFormat(CameraFeed feed, int index)
    {
        var parameters = new Godot.Collections.Dictionary();
        if (IsExtensionFeed(feed))
        {
            feed.Call("set_format", index, parameters);
        }
        else
        {
            feed.SetFormat(index, parameters);
        }
    }

    private void SearchCamera(double now)
    {
        int count = CameraServer.GetFeedCount();
        if (count > 0 && double.IsNaN(_firstFeedAt))
        {
            _firstFeedAt = now;
        }

        bool timeout = now - _searchStarted > _cameraSearchTimeout;
        bool graceOver = !double.IsNaN(_firstFeedAt) && now - _firstFeedAt > _graceAfterFirstFeed;
        if (!timeout && !graceOver)
        {
            return;
        }

        var candidates = new List<(CameraFeed Feed, int Format)>();
        for (int i = 0; i < count; i++)
        {
            CameraFeed feed = CameraServer.GetFeed(i);
            int format = FindFormat(feed);
            if (format >= 0)
            {
                candidates.Add((feed, format));
            }
        }

        GD.Print($"The camera server reports {count} feed(s), {candidates.Count} compatible.");

        if (candidates.Count == 0)
        {
            SetStatus(
                ServiceStatus.NoCamera,
                _noCameraReason switch
                {
                    "unsupported" => "The camera does not work on Windows without the camera extension.",
                    "denied" => "Windows does not allow the camera (Settings, Privacy, Camera).",
                    _ => count == 0 ? "No camera found." : "No camera supports 640x480, which the vision needs.",
                }
            );
            return;
        }

        var (chosen, formatIndex) = candidates[Math.Clamp(CameraIndex, 0, candidates.Count - 1)];
        StartCamera(chosen, formatIndex);
    }

    /// <summary>
    /// Find the 640x480 format, preferring YUYV; return -1 if there is none, and
    /// <see cref="_anyFormat"/> if the feed lists no formats at all.
    /// </summary>
    /// <remarks>
    /// Godot lists the formats only on Linux; elsewhere (e.g., on macOS) the feed
    /// runs at the resolution of the system, which the pose letterboxes anyhow.
    /// </remarks>
    private static int FindFormat(CameraFeed feed)
    {
        var formats = GetFormats(feed);
        if (formats.Count == 0)
        {
            return _anyFormat;
        }

        int fallback = -1;
        for (int i = 0; i < formats.Count; i++)
        {
            var format = formats[i].AsGodotDictionary();
            int width = format.ContainsKey("width") ? format["width"].AsInt32() : 0;
            int height = format.ContainsKey("height") ? format["height"].AsInt32() : 0;
            string pixelFormat = format.ContainsKey("format") ? format["format"].AsString() : "";
            if (width != 640 || height != 480)
            {
                continue;
            }

            // NOTE (mristin):
            // V4L2 on Linux calls the format YUYV, Media Foundation on Windows YUY2.
            if (pixelFormat.StartsWith("YUYV") || pixelFormat.StartsWith("YUY2"))
            {
                return i;
            }

            fallback = fallback < 0 ? i : fallback;
        }

        return fallback;
    }

    /// <summary>The format index of a feed which lists no formats (see <see cref="FindFormat"/>).</summary>
    private const int _anyFormat = int.MaxValue;

    /// <summary>Keep the camera at its full frame rate in dim light, too (see <see cref="LinuxCameraControls"/>).</summary>
    private void KeepFullFrameRate()
    {
        if (_feed == null)
        {
            return;
        }

        // NOTE (mristin):
        // Only a nicety: whatever goes wrong, the camera runs as it would anyway.
        try
        {
            var devices = LinuxCameraControls.KeepFullFrameRate(_feed.GetName());
            if (devices.Count > 0)
            {
                GD.Print($"Switched off the dynamic frame rate of the camera on {string.Join(", ", devices)}.");
            }
        }
        catch (Exception exception)
        {
            GD.PushWarning($"Could not keep the full frame rate of the camera: {exception.Message}");
        }
    }

    private void StartCamera(CameraFeed feed, int formatIndex)
    {
        string description = formatIndex == _anyFormat
            ? $"{feed.GetName()}, the default format"
            : $"{feed.GetName()}, format #{formatIndex}: {GetFormats(feed)[formatIndex]}";
        GD.Print($"Starting the camera {description}");
        _feed = feed;
        if (formatIndex != _anyFormat)
        {
            SetFormat(_feed, formatIndex);
        }

        _feed.FeedIsActive = true;
        _nextActivationAttempt = Now + _activationRetryPeriod;
        KeepFullFrameRate();

        CameraTexture = new CameraTexture { CameraFeedId = _feed.GetId(), CameraIsActive = true };
        _cbcrTexture = new CameraTexture
        {
            CameraFeedId = _feed.GetId(),
            WhichFeed = CameraServer.FeedImage.CbcrImage,
            CameraIsActive = true,
        };
        _feed.FrameChanged += OnFrameChanged;

        SetStatus(ServiceStatus.LoadingModels, "Loading the models...");

        byte[] rtmo = FileAccess.GetFileAsBytes(RtmoModelPath);
        byte[] rtmPose = FileAccess.GetFileAsBytes(RtmPoseModelPath);
        int threads = Threads;
        _running = true;
        _poseThread = new Thread(() => PoseLoop(rtmo, rtmPose, threads))
        {
            IsBackground = true,
            Name = "Pose",
            Priority = ThreadPriority.BelowNormal,
        };
        _poseThread.Start();

        if (FileAccess.FileExists(HandModelPath))
        {
            byte[] handModel = FileAccess.GetFileAsBytes(HandModelPath);
            _handThread = new Thread(() => HandLoop(handModel))
            {
                IsBackground = true,
                Name = "Hands",
                Priority = ThreadPriority.BelowNormal,
            };
            _handThread.Start();
        }
        else
        {
            GD.PushWarning($"The hand model {HandModelPath} is missing; the screens work only with the mouse.");
        }
    }

    private void OnFrameChanged()
    {
        if (_shutDown)
        {
            return;
        }

        if (!_fullFrameRateKept)
        {
            // NOTE (mristin):
            // Once more with the first frame: a driver may reset the controls when
            // the camera starts to stream.
            _fullFrameRateKept = true;
            KeepFullFrameRate();
        }

        if (CameraTexture == null || _feed == null)
        {
            return;
        }

        bool forPose = _poseSlot.Requested;
        bool forHands = _handTracking && _handSlot.Requested;
        bool twoPlanes = _feed.GetDatatype() == CameraFeed.FeedDataType.YcbcrSep;

        // NOTE (mristin):
        // While we save the frames, we take every frame of the camera, so
        // that the pictures are the whole video, not only what the vision saw.
        bool forFrames = _frameQueue != null;
        if (!forPose && !forHands && !twoPlanes && !forFrames)
        {
            return;
        }

        byte[] rgb;
        int width;
        int height;
        if (twoPlanes)
        {
            // NOTE (mristin):
            // A two-plane feed has no RGB texture, so we convert it ourselves, on
            // every frame, as the preview needs it, too.
            Image? luma = CameraTexture.GetImage();
            Image? chroma = _cbcrTexture?.GetImage();
            if (luma == null || luma.IsEmpty() || chroma == null || chroma.IsEmpty())
            {
                return;
            }

            (rgb, width, height) = YcbcrToRgb(luma, chroma, _maxYcbcrWidth);
            var preview = Image.CreateFromData(width, height, false, Image.Format.Rgb8, rgb);
            if (_ycbcrPreview == null || _ycbcrPreview.GetSize() != preview.GetSize())
            {
                _ycbcrPreview = ImageTexture.CreateFromImage(preview);
            }
            else
            {
                _ycbcrPreview.Update(preview);
            }

            if (!forPose && !forHands && !forFrames)
            {
                return;
            }
        }
        else
        {
            Image? image = CameraTexture.GetImage();
            if (image == null || image.IsEmpty())
            {
                return;
            }

            if (image.GetFormat() != Image.Format.Rgb8)
            {
                image.Convert(Image.Format.Rgb8);
            }

            rgb = image.GetData();
            width = image.GetWidth();
            height = image.GetHeight();
        }

        // NOTE (mristin):
        // We copy the raw bytes on the main thread so that the pose thread
        // never touches any engine objects.
        var frame = new Frame(rgb, width, height, Now);
        SaveFrame(frame);
        if (forPose)
        {
            _poseSlot.Put(frame);
        }

        if (forHands)
        {
            _handSlot.Put(frame);
        }
    }

    /// <summary>Convert a Y plane and a CbCr plane of the camera to RGB8.</summary>
    private static (byte[] Rgb, int Width, int Height) YcbcrToRgb(Image luma, Image chroma, int maxWidth)
    {
        if (luma.GetFormat() != Image.Format.R8)
        {
            luma.Convert(Image.Format.R8);
        }

        if (chroma.GetFormat() != Image.Format.Rg8)
        {
            chroma.Convert(Image.Format.Rg8);
        }

        return YcbcrConverter.ToRgb(
            luma.GetData(), luma.GetWidth(), luma.GetHeight(),
            chroma.GetData(), chroma.GetWidth(), chroma.GetHeight(),
            maxWidth);
    }

    /// <summary>
    /// Activate the feed again if it did not start, which happens on macOS on the
    /// first start: the feed asks for the permission and stays off even when the
    /// players grant it.
    /// </summary>
    private void RetryActivation(double now)
    {
        if (_feed == null || _feed.FeedIsActive || double.IsNaN(_nextActivationAttempt)
            || now < _nextActivationAttempt)
        {
            return;
        }

        _nextActivationAttempt = now + _activationRetryPeriod;
        GD.Print("The camera did not start; trying again (maybe the camera permission was just granted).");
        _feed.FeedIsActive = true;
        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = true;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = true;
        }
    }

    /// <summary>Ask for the next camera frame and wait for it; null on a timeout or the exit.</summary>
    private Frame? NextFrame(FrameSlot slot)
    {
        slot.Requested = true;
        if (!slot.Ready.WaitOne(500) || !_running)
        {
            return null;
        }

        return slot.Take();
    }

    private void HandLoop(byte[] model)
    {
        YoloxHeadDetector? detector = null;
        try
        {
            detector = new YoloxHeadDetector(model);
            var heads = new List<Detection>();
            while (_running)
            {
                if (!_handTracking)
                {
                    Thread.Sleep(50);
                    continue;
                }

                var frame = NextFrame(_handSlot);
                if (frame == null)
                {
                    continue;
                }

                detector.Detect(frame, heads);
                var hands = new List<BoundingBox>();
                foreach (var hand in detector.Hands)
                {
                    hands.Add(hand.Box);
                }

                Volatile.Write(ref _latestHands, new HandSnapshot
                {
                    Timestamp = frame.Timestamp,
                    Width = frame.Width,
                    Height = frame.Height,
                    Hands = hands,
                });
            }
        }
        catch (Exception exception)
        {
            // NOTE (mristin):
            // Without the hands, the screens still work with the mouse.
            GD.PushWarning($"The hand detector stopped: {exception}");
        }
        finally
        {
            detector?.Dispose();
        }
    }

    private void PoseLoop(byte[] rtmo, byte[] rtmPose, int threads)
    {
        PoseFollower? follower = null;
        try
        {
            follower = new PoseFollower(rtmo, rtmPose, threads);
            Callable.From(() => SetStatus(ServiceStatus.Running, "")).CallDeferred();

            while (_running)
            {
                var frame = NextFrame(_poseSlot);
                if (frame != null)
                {
                    Volatile.Write(ref _latest, follower.Process(frame, _threadPlayerCount));
                }
            }
        }
        catch (Exception exception)
        {
            GD.PushError($"The vision failed: {exception}");
            string message = $"The vision failed: {exception.Message}";
            Callable.From(() => SetStatus(ServiceStatus.Failed, message)).CallDeferred();
        }
        finally
        {
            follower?.Dispose();
        }
    }

    private void SetStatus(ServiceStatus status, string message)
    {
        Status = status;
        StatusMessage = message;
        GD.Print($"Vision: {status}: {message}");
    }

    public override void _Notification(int what)
    {
        if (what == NotificationWMCloseRequest)
        {
            Shutdown();
        }
    }

    public override void _ExitTree() => Shutdown();

    /// <summary>
    /// Stop the camera, the pose thread and the recording; call it before
    /// quitting, so that no camera frame arrives while the engine shuts down.
    /// Calling it again does nothing.
    /// </summary>
    public void Shutdown()
    {
        if (_shutDown)
        {
            return;
        }

        _shutDown = true;
        StopRecording();
        _running = false;
        _poseSlot.Ready.Set();
        _handSlot.Ready.Set();
        _poseThread?.Join(2000);
        _poseThread = null;
        _handThread?.Join(2000);
        _handThread = null;

        if (_feed != null)
        {
            _feed.FrameChanged -= OnFrameChanged;
            _feed.FeedIsActive = false;
            _feed = null;
        }

        if (CameraTexture != null)
        {
            CameraTexture.CameraIsActive = false;
        }

        if (_cbcrTexture != null)
        {
            _cbcrTexture.CameraIsActive = false;
        }

        // NOTE (mristin):
        // The extension removes its feeds when it is freed, so it goes last.
        _cameraExtension = null;
    }
}
