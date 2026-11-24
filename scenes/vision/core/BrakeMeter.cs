using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>
    /// Tell whether the player brakes: both hands raised high above the head.
    /// </summary>
    /// <remarks>
    /// <para>
    /// An arm is raised when its wrist is <see cref="RaiseAbove"/> above the
    /// head; raised high, the hand may leave the top of the picture, so while
    /// the wrist is not seen, the elbow raised <see cref="ElbowAbove"/> above
    /// the shoulder counts, too. The player brakes once both arms are raised,
    /// and lets go of the brake once an arm comes down below
    /// <see cref="ReleaseAbove"/> (lower than the raise, so that the brake does
    /// not flicker), or once we do not see the arms for <see cref="LoseAfter"/>.
    /// </para>
    /// <para>
    /// The heights are in the unit of the player (see <see cref="BodyScale"/>),
    /// y growing downwards as in the picture. The instance is not thread-safe.
    /// </para>
    /// </remarks>
    public sealed class BrakeMeter
    {
        /// <summary>The wrist is raised this far above the head, in units.</summary>
        public float RaiseAbove = 0.3f;

        /// <summary>The raised wrist comes down when it is no more than this far above the head, in units.</summary>
        public float ReleaseAbove = 0.0f;

        /// <summary>While the wrist is not seen, the elbow is raised this far above the shoulder, in units.</summary>
        public float ElbowAbove = 0.5f;

        /// <summary>Let go of the brake after this many seconds without the arms.</summary>
        public double LoseAfter = 0.5;

        /// <summary>Whether the player brakes now.</summary>
        public bool Braking { get; private set; }

        private double _lastSeen = double.NaN;

        /// <summary>
        /// Observe the player at the time <paramref name="t"/>: the height of the
        /// head, and of each wrist, elbow and shoulder (the player's left, then
        /// right), in frame pixels (NaN where not seen), with the unit of the
        /// player in frame pixels. Return whether the player brakes.
        /// </summary>
        public bool Observe(
            double t,
            float headY,
            float leftWristY,
            float rightWristY,
            float leftElbowY,
            float rightElbowY,
            float leftShoulderY,
            float rightShoulderY,
            float unit)
        {
            if (float.IsNaN(headY) || float.IsNaN(unit) || unit <= 0f)
            {
                if (!double.IsNaN(_lastSeen) && t - _lastSeen > LoseAfter)
                {
                    Braking = false;
                }

                return Braking;
            }

            float above = Braking ? ReleaseAbove : RaiseAbove;
            bool? left = Raised(headY, leftWristY, leftElbowY, leftShoulderY, unit, above);
            bool? right = Raised(headY, rightWristY, rightElbowY, rightShoulderY, unit, above);
            if (left == null || right == null)
            {
                // NOTE (mristin):
                // An arm out of sight keeps the brake as it was, for a while.
                if (!double.IsNaN(_lastSeen) && t - _lastSeen > LoseAfter)
                {
                    Braking = false;
                }

                return Braking;
            }

            _lastSeen = t;
            Braking = left.Value && right.Value;
            return Braking;
        }

        /// <summary>Whether the arm is raised; null if we can not tell.</summary>
        private bool? Raised(float headY, float wristY, float elbowY, float shoulderY, float unit, float above)
        {
            if (!float.IsNaN(wristY))
            {
                return (headY - wristY) / unit >= above;
            }

            if (!float.IsNaN(elbowY) && !float.IsNaN(shoulderY))
            {
                return (shoulderY - elbowY) / unit >= ElbowAbove;
            }

            return null;
        }

        /// <summary>Forget the player.</summary>
        public void Reset()
        {
            Braking = false;
            _lastSeen = double.NaN;
        }
    }
}  // namespace DrunkenVikings.Vision
