using System;
using System.Collections.Generic;
using System.Diagnostics;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>Tell which model found a pose.</summary>
    public enum PoseSource
    {
        /// <summary>Nobody was found.</summary>
        None,

        /// <summary>RTMO, which looks at the whole picture.</summary>
        Rtmo,

        /// <summary>RTMPose-t, which follows the player in the box of the previous frame.</summary>
        RtmPose,
    }

    /// <summary>Hold what the vision found in one frame; immutable.</summary>
    public sealed class VisionSnapshot
    {
        /// <summary>The time of the frame, on the clock of the vision service.</summary>
        public double Timestamp { get; init; }

        public int Width { get; init; }
        public int Height { get; init; }

        /// <summary>
        /// The pose of each player, or null for a player who is not in the
        /// picture; with two players, each in their own half of the picture (see
        /// <see cref="PlayerSplit"/>).
        /// </summary>
        public IReadOnlyList<Pose?> Players { get; init; } = Array.Empty<Pose?>();

        /// <summary>Which model found the pose of each player.</summary>
        public IReadOnlyList<PoseSource> Sources { get; init; } = Array.Empty<PoseSource>();

        /// <summary>How long the poses took, in milliseconds.</summary>
        public double InferenceMs { get; init; }
    }

    /// <summary>Find the players with RTMO, and follow each with RTMPose-t.</summary>
    /// <remarks>
    /// <para>
    /// RTMPose-t follows a player on every frame, in the box of their previous
    /// pose. RTMO, which is slower, runs only while some player is not followed:
    /// at the start, and when a player was lost or left their half of the
    /// picture.
    /// </para>
    /// <para>The instance is not thread-safe; use it from a single thread only.</para>
    /// </remarks>
    public sealed class PoseFollower : IDisposable
    {
        /// <summary>RTMO picks the players by the key points of at least this score.</summary>
        public float KeypointThreshold = 0.5f;

        private readonly RtmoPoseEstimator _finder;
        private readonly RtmPoseTracker[] _trackers;
        private readonly List<Pose> _found = new();

        /// <param name="rtmoModel">The bytes of the RTMO model.</param>
        /// <param name="rtmPoseModel">The bytes of the RTMPose-t model.</param>
        public PoseFollower(byte[] rtmoModel, byte[] rtmPoseModel, int threads = 2)
        {
            _finder = new RtmoPoseEstimator(rtmoModel, threads);
            _trackers = new RtmPoseTracker[PlayerSplit.MaxPlayers];
            try
            {
                for (int i = 0; i < _trackers.Length; i++)
                {
                    _trackers[i] = new RtmPoseTracker(rtmPoseModel, 1);
                }
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        /// <summary>Find the poses of the players (1 or 2) in the frame.</summary>
        public VisionSnapshot Process(Frame frame, int playerCount = 1)
        {
            var stopwatch = Stopwatch.StartNew();
            int count = Math.Clamp(playerCount, 1, PlayerSplit.MaxPlayers);
            var players = new Pose?[count];
            var sources = new PoseSource[count];

            bool anyLost = false;
            for (int i = 0; i < count; i++)
            {
                var pose = _trackers[i].Track(frame);
                if (pose != null && !InHalf(pose, frame.Width, i, count))
                {
                    _trackers[i].Lose();
                    pose = null;
                }

                players[i] = pose;
                sources[i] = pose != null ? PoseSource.RtmPose : PoseSource.None;
                anyLost |= pose == null;
            }

            for (int i = count; i < _trackers.Length; i++)
            {
                _trackers[i].Lose();
            }

            if (anyLost)
            {
                _finder.Estimate(frame, _found);
                for (int i = 0; i < count; i++)
                {
                    if (players[i] != null)
                    {
                        continue;
                    }

                    var pose = PlayerSelection.Pick(_found, KeypointThreshold, frame.Width, i, count);
                    if (pose != null && _trackers[i].Seed(pose))
                    {
                        players[i] = pose;
                        sources[i] = PoseSource.Rtmo;
                    }
                }
            }

            return new VisionSnapshot
            {
                Timestamp = frame.Timestamp,
                Width = frame.Width,
                Height = frame.Height,
                Players = players,
                Sources = sources,
                InferenceMs = stopwatch.Elapsed.TotalMilliseconds,
            };
        }

        /// <summary>Whether the pose is still in the half of the player (any pose with one player).</summary>
        private bool InHalf(Pose pose, int frameWidth, int player, int playerCount)
        {
            if (playerCount <= 1)
            {
                return true;
            }

            var head = pose.Head(KeypointThreshold);
            float x = head?.X ?? pose.Box.CenterX;
            return PlayerSplit.PlayerOf(x, frameWidth, playerCount) == player;
        }

        public void Dispose()
        {
            foreach (var tracker in _trackers)
            {
                tracker?.Dispose();
            }

            _finder?.Dispose();
        }
    }
}  // namespace DrunkenVikings.Vision
