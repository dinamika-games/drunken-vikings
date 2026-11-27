using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>
    /// Record what the vision measured, as JSON lines, to study the rowing of
    /// real players (see dev/rowing/).
    /// </summary>
    /// <remarks>
    /// <para>
    /// Only numbers are recorded: where the joints are, and the signals of the
    /// rowing. The camera pictures are not part of the recording (see the
    /// frames of the vision service, which are saved only on request).
    /// </para>
    /// <para>Every line is one JSON object with its "kind":</para>
    /// <list type="bullet">
    /// <item>"start": the size of the frames, the number of players and the note of the session;</item>
    /// <item>
    /// "pose": for each player (null if not seen), the 17 key points as x, y
    /// and score ("keypoints", in the pixels of the frame, not mirrored), the
    /// model which found them ("source") and the <see cref="RowingSignals"/>
    /// ("signals", by name; null where unknown);
    /// </item>
    /// <item>"frame": a camera frame saved as a picture, with its "index";</item>
    /// <item>"mark": e.g., when the player was called to pull, with its "name".</item>
    /// </list>
    /// <para>
    /// Each line has the time "t" in seconds and the "label" of what the player
    /// was asked to do. The instance is not thread-safe; use it from a single
    /// thread only.
    /// </para>
    /// </remarks>
    public sealed class VisionRecorder : IDisposable
    {
        private readonly StreamWriter _writer;

        /// <summary>What the player is asked to do now, e.g., "row slow".</summary>
        public string Label = "";

        /// <summary>How many lines were written.</summary>
        public int Lines { get; private set; }

        public VisionRecorder(string path)
        {
            var directory = Path.GetDirectoryName(Path.GetFullPath(path));
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            _writer = new StreamWriter(path, append: false) { AutoFlush = false };
        }

        /// <summary>Write the start of the recording.</summary>
        public void RecordStart(double t, int width, int height, int players, string note)
        {
            Write(new Dictionary<string, object?>
            {
                ["kind"] = "start",
                ["t"] = t,
                ["label"] = Label,
                ["width"] = width,
                ["height"] = height,
                ["players"] = players,
                ["note"] = note,
                ["signals"] = RowingSignals.Names,
                ["time"] = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
            });
        }

        /// <summary>Write the poses of the players and their signals.</summary>
        public void RecordPose(VisionSnapshot snapshot, IReadOnlyList<RowingSignals> signals)
        {
            var list = new List<object?>();
            for (int i = 0; i < snapshot.Players.Count; i++)
            {
                var pose = snapshot.Players[i];
                if (pose == null)
                {
                    list.Add(null);
                    continue;
                }

                var points = new float[Pose.KeypointCount * 3];
                for (int k = 0; k < Pose.KeypointCount; k++)
                {
                    points[k * 3] = MathF.Round(pose.Keypoints[k].X, 2);
                    points[k * 3 + 1] = MathF.Round(pose.Keypoints[k].Y, 2);
                    points[k * 3 + 2] = MathF.Round(pose.Keypoints[k].Score, 3);
                }

                var named = new Dictionary<string, float?>();
                if (i < signals.Count)
                {
                    var values = signals[i].ToArray();
                    for (int s = 0; s < values.Length; s++)
                    {
                        named[RowingSignals.Names[s]] = float.IsNaN(values[s]) ? null : MathF.Round(values[s], 4);
                    }
                }

                list.Add(new Dictionary<string, object?>
                {
                    ["keypoints"] = points,
                    ["source"] = i < snapshot.Sources.Count ? snapshot.Sources[i].ToString() : "",
                    ["signals"] = named,
                });
            }

            Write(new Dictionary<string, object?>
            {
                ["kind"] = "pose",
                ["t"] = snapshot.Timestamp,
                ["label"] = Label,
                ["ms"] = Math.Round(snapshot.InferenceMs, 2),
                ["players"] = list,
            });
        }

        /// <summary>Write that the camera frame of the time <paramref name="t"/> was saved as the picture <paramref name="index"/>.</summary>
        public void RecordFrame(double t, int index)
        {
            Write(new Dictionary<string, object?> { ["kind"] = "frame", ["t"] = t, ["label"] = Label, ["index"] = index });
        }

        /// <summary>Write a mark at the time <paramref name="t"/>, e.g., when the player was called to pull.</summary>
        public void RecordMark(double t, string name)
        {
            Write(new Dictionary<string, object?> { ["kind"] = "mark", ["t"] = t, ["label"] = Label, ["name"] = name });
        }

        private void Write(Dictionary<string, object?> line)
        {
            _writer.WriteLine(JsonSerializer.Serialize(line));
            Lines++;

            // NOTE (mristin):
            // Flush now and then, so that a crash loses at most a few lines.
            if (Lines % 50 == 0)
            {
                _writer.Flush();
            }
        }

        public void Dispose()
        {
            _writer.Flush();
            _writer.Dispose();
        }
    }
}  // namespace DrunkenVikings.Vision
