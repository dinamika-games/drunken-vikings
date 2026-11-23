using System;
using System.Collections.Generic;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>
    /// Hold the candidate signals of the rowing and the steering, measured on
    /// one pose; NaN where the key points are missing.
    /// </summary>
    /// <remarks>
    /// <para>
    /// We do not know yet which movements the game will use, so we measure
    /// several candidates and record them (see dev/rowing/): for the stroke, the
    /// torso which leans back and forth and the hands which reach out and pull
    /// in; for the steering, the hands which go to one side (rowing on one side,
    /// or a Russian twist), the torso which leans or twists to one side, and the
    /// head which turns.
    /// </para>
    /// <para>
    /// The lengths are in the <see cref="Unit"/> of the player (about the width
    /// of the shoulders, see <see cref="BodyScale"/>), so that they do not depend
    /// on how far the player sits from the camera. "Right" is the player's right
    /// (on the left of the camera frame, which is not mirrored): the signals of
    /// the sides are positive to the player's right.
    /// </para>
    /// </remarks>
    public readonly struct RowingSignals
    {
        /// <summary>The names of the signals, in the order of <see cref="ToArray"/>.</summary>
        public static readonly string[] Names =
        {
            "unit",
            "torso_up",
            "torso_lean",
            "head_up",
            "head_y",
            "shoulder_y",
            "hands_up",
            "hands_side",
            "reach_left",
            "reach_right",
            "hand_spread",
            "elbow_spread",
            "shoulder_tilt",
            "shoulder_width",
            "shoulder_shift",
            "head_side",
        };

        /// <summary>The unit of length of the player, in frame pixels.</summary>
        public float Unit { get; init; }

        /// <summary>
        /// How far the shoulders are above the hips, in units. Leaning forward or
        /// back (towards or away from the camera) shortens it.
        /// </summary>
        public float TorsoUp { get; init; }

        /// <summary>
        /// The angle of the torso (from the hips to the shoulders) from the
        /// vertical of the picture, in degrees, positive to the player's right.
        /// Facing the camera, this is the lean to the side; side-on, the lean
        /// forward and back.
        /// </summary>
        public float TorsoLean { get; init; }

        /// <summary>How far the head is above the hips, in units.</summary>
        public float HeadUp { get; init; }

        /// <summary>
        /// The height of the head in the picture, as a share of the picture's
        /// height from its top (it grows as the head goes down). It needs no
        /// hips, which the knees may hide when the player sits.
        /// </summary>
        public float HeadY { get; init; }

        /// <summary>The height of the middle of the shoulders, as <see cref="HeadY"/>.</summary>
        public float ShoulderY { get; init; }

        /// <summary>How far the middle of the wrists is above the middle of the shoulders, in units.</summary>
        public float HandsUp { get; init; }

        /// <summary>
        /// How far the middle of the wrists is to the player's right of the middle
        /// of the hips (of the shoulders, if the hips are missing), in units.
        /// </summary>
        public float HandsSide { get; init; }

        /// <summary>How far the left wrist is from the left shoulder in the picture, in units.</summary>
        public float ReachLeft { get; init; }

        /// <summary>How far the right wrist is from the right shoulder in the picture, in units.</summary>
        public float ReachRight { get; init; }

        /// <summary>How far the wrists are apart, in units.</summary>
        public float HandSpread { get; init; }

        /// <summary>How far the elbows are apart sideways, in units; pulling the oar spreads them.</summary>
        public float ElbowSpread { get; init; }

        /// <summary>
        /// The angle of the line of the shoulders, in degrees, positive when the
        /// right shoulder is lower (leaning to the player's right).
        /// </summary>
        public float ShoulderTilt { get; init; }

        /// <summary>
        /// The width of the shoulders now, in units; it shrinks below 1 as the
        /// player twists (and the unit keeps the width facing the camera).
        /// </summary>
        public float ShoulderWidth { get; init; }

        /// <summary>
        /// How far the middle of the shoulders is to the player's right of the
        /// middle of the hips, in units.
        /// </summary>
        public float ShoulderShift { get; init; }

        /// <summary>
        /// How far the nose is to the player's right of the middle of the
        /// shoulders, in units; it follows the turn of the head.
        /// </summary>
        public float HeadSide { get; init; }

        /// <summary>The signals in the order of <see cref="Names"/>.</summary>
        public float[] ToArray() =>
            new[]
            {
                Unit,
                TorsoUp,
                TorsoLean,
                HeadUp,
                HeadY,
                ShoulderY,
                HandsUp,
                HandsSide,
                ReachLeft,
                ReachRight,
                HandSpread,
                ElbowSpread,
                ShoulderTilt,
                ShoulderWidth,
                ShoulderShift,
                HeadSide,
            };

        /// <summary>All the signals unknown.</summary>
        public static RowingSignals Unknown => Measure(null, float.NaN, 1, 0.3f);

        /// <summary>
        /// Measure the signals on the pose, in the <paramref name="unit"/> (in
        /// frame pixels), using only the key points of at least the
        /// <paramref name="threshold"/>.
        /// </summary>
        public static RowingSignals Measure(Pose? pose, float unit, int frameHeight, float threshold)
        {
            float nan = float.NaN;
            if (pose == null || float.IsNaN(unit) || unit <= 0f)
            {
                return new RowingSignals
                {
                    Unit = nan,
                    TorsoUp = nan,
                    TorsoLean = nan,
                    HeadUp = nan,
                    HeadY = nan,
                    ShoulderY = nan,
                    HandsUp = nan,
                    HandsSide = nan,
                    ReachLeft = nan,
                    ReachRight = nan,
                    HandSpread = nan,
                    ElbowSpread = nan,
                    ShoulderTilt = nan,
                    ShoulderWidth = nan,
                    ShoulderShift = nan,
                    HeadSide = nan,
                };
            }

            (float X, float Y)? Point(BodyPart part) =>
                pose.Has(part, threshold) ? (pose[part].X, pose[part].Y) : null;

            (float X, float Y)? Middle(BodyPart a, BodyPart b)
            {
                var pa = Point(a);
                var pb = Point(b);
                return pa != null && pb != null ? ((pa.Value.X + pb.Value.X) / 2f, (pa.Value.Y + pb.Value.Y) / 2f) : null;
            }

            float Distance((float X, float Y)? a, (float X, float Y)? b) =>
                a != null && b != null
                    ? MathF.Sqrt((a.Value.X - b.Value.X) * (a.Value.X - b.Value.X) + (a.Value.Y - b.Value.Y) * (a.Value.Y - b.Value.Y)) / unit
                    : nan;

            var shoulders = Middle(BodyPart.LeftShoulder, BodyPart.RightShoulder);
            var hips = Middle(BodyPart.LeftHip, BodyPart.RightHip);
            var wrists = Middle(BodyPart.LeftWrist, BodyPart.RightWrist);
            var head = pose.Head(threshold);
            var nose = Point(BodyPart.Nose);
            var leftShoulder = Point(BodyPart.LeftShoulder);
            var rightShoulder = Point(BodyPart.RightShoulder);
            var leftElbow = Point(BodyPart.LeftElbow);
            var rightElbow = Point(BodyPart.RightElbow);
            var leftWrist = Point(BodyPart.LeftWrist);
            var rightWrist = Point(BodyPart.RightWrist);

            // NOTE (mristin):
            // The frame is not mirrored, so the player's right is towards the
            // smaller x: the signals of the sides take x the other way round.
            var center = hips ?? shoulders;
            float height = Math.Max(1, frameHeight);

            return new RowingSignals
            {
                Unit = unit,
                TorsoUp = shoulders != null && hips != null ? (hips.Value.Y - shoulders.Value.Y) / unit : nan,
                TorsoLean = shoulders != null && hips != null
                    ? Degrees(MathF.Atan2(hips.Value.X - shoulders.Value.X, hips.Value.Y - shoulders.Value.Y))
                    : nan,
                HeadUp = head != null && hips != null ? (hips.Value.Y - head.Value.Y) / unit : nan,
                HeadY = head != null ? head.Value.Y / height : nan,
                ShoulderY = shoulders != null ? shoulders.Value.Y / height : nan,
                HandsUp = wrists != null && shoulders != null ? (shoulders.Value.Y - wrists.Value.Y) / unit : nan,
                HandsSide = wrists != null && center != null ? (center.Value.X - wrists.Value.X) / unit : nan,
                ReachLeft = Distance(leftWrist, leftShoulder),
                ReachRight = Distance(rightWrist, rightShoulder),
                HandSpread = Distance(leftWrist, rightWrist),
                ElbowSpread = leftElbow != null && rightElbow != null
                    ? MathF.Abs(leftElbow.Value.X - rightElbow.Value.X) / unit
                    : nan,
                ShoulderTilt = leftShoulder != null && rightShoulder != null
                    ? Degrees(MathF.Atan2(
                        rightShoulder.Value.Y - leftShoulder.Value.Y,
                        leftShoulder.Value.X - rightShoulder.Value.X))
                    : nan,
                ShoulderWidth = Distance(leftShoulder, rightShoulder),
                ShoulderShift = shoulders != null && hips != null ? (hips.Value.X - shoulders.Value.X) / unit : nan,
                HeadSide = nose != null && shoulders != null ? (shoulders.Value.X - nose.Value.X) / unit : nan,
            };
        }

        private static float Degrees(float radians) => radians * 180f / MathF.PI;
    }

    /// <summary>
    /// Keep the unit of length of a player: the widest the shoulders were of
    /// late, so that a twist (which narrows the shoulders in the picture) does
    /// not change the unit.
    /// </summary>
    /// <remarks>
    /// The width falls back on the ears and the eyes (see <see cref="Pose.Unit"/>)
    /// when a shoulder is missing. The instance is not thread-safe.
    /// </remarks>
    public sealed class BodyScale
    {
        /// <summary>Keep the widest of the last this many seconds.</summary>
        public double Window = 4.0;

        private readonly LinkedList<(double T, float Width)> _widths = new();

        /// <summary>The unit in frame pixels, or NaN before the first width.</summary>
        public float Unit { get; private set; } = float.NaN;

        /// <summary>Observe the pose at the time <paramref name="t"/>, in seconds, and return the unit.</summary>
        public float Observe(double t, Pose? pose, float threshold)
        {
            while (_widths.First != null && t - _widths.First.Value.T > Window)
            {
                _widths.RemoveFirst();
            }

            var width = pose?.Unit(threshold);
            if (width != null)
            {
                // NOTE (mristin):
                // Keep the widths falling from the oldest to the newest, so that
                // the first is always the widest of the window.
                while (_widths.Last != null && _widths.Last.Value.Width <= width.Value)
                {
                    _widths.RemoveLast();
                }

                _widths.AddLast((t, width.Value));
            }

            Unit = _widths.First != null ? _widths.First.Value.Width : float.NaN;
            return Unit;
        }

        public void Reset()
        {
            _widths.Clear();
            Unit = float.NaN;
        }
    }
}  // namespace DrunkenVikings.Vision
