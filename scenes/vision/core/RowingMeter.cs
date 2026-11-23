using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>
    /// Turn the head of a player into the rowing: the strokes, and the
    /// steering.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The player sits facing the camera. A stroke (leaning back and pulling,
    /// then reaching forward again) moves the head up and down in the picture by
    /// about three quarters of the unit; we count a stroke each time the head
    /// came back up by <see cref="StrokeDepth"/> after it went down as much.
    /// </para>
    /// <para>
    /// To steer, the player goes sideways with the whole upper body, the head
    /// by a unit or more. The steering is how far the head is to the side of
    /// home, where the head stays while the player rows (which we learn on the
    /// way). While the player steers, the head goes down a little as well, so
    /// we count no strokes then: the player either rows, or glides and steers.
    /// </para>
    /// <para>
    /// All the lengths are in the unit of the player (see <see cref="BodyScale"/>),
    /// and "right" is the player's right: the frame is not mirrored, so the
    /// player's right is towards the smaller x. The instance is not thread-safe.
    /// </para>
    /// </remarks>
    public sealed class RowingMeter
    {
        /// <summary>The head must go down and back up by this much for a stroke, in units.</summary>
        public float StrokeDepth = 0.25f;

        /// <summary>No strokes count while the head is this far to the side, in units.</summary>
        public float SteeringFrom = 0.4f;

        /// <summary>The steering starts this far to the side, in units.</summary>
        public float DeadZone = 0.3f;

        /// <summary>The steering is full this far to the side, in units.</summary>
        public float FullSteer = 1.0f;

        /// <summary>Home follows the head within the dead zone with this time constant, in seconds.</summary>
        public double HomeFollow = 5.0;

        /// <summary>Home drifts towards the head anywhere with this time constant, in seconds, e.g., when the player moved.</summary>
        public double HomeDrift = 30.0;

        /// <summary>Forget the player after this many seconds without a head.</summary>
        public double LoseAfter = 2.0;

        /// <summary>The range of the stroke (see <see cref="Pull"/>) forgets old strokes with this time constant, in seconds.</summary>
        public double RangeMemory = 4.0;

        /// <summary>How many strokes were counted.</summary>
        public int Strokes { get; private set; }

        /// <summary>When the last stroke was counted, in seconds; NaN before the first.</summary>
        public double LastStrokeAt { get; private set; } = double.NaN;

        /// <summary>How far the head went down and up in the last stroke, in units.</summary>
        public float LastStrokeDepth { get; private set; }

        /// <summary>How far the head is to the player's right of home, in units; 0 before home.</summary>
        public float Shift { get; private set; }

        /// <summary>The steering in [-1, 1], positive to the player's right.</summary>
        public float Steer { get; private set; }

        /// <summary>
        /// How far the player is through the stroke now, following the head:
        /// 0 at the top (reaching forward, the oars ready to dip in), 1 at the
        /// bottom (leaning back, the pull done); NaN while the player does not
        /// row (the head does not go up and down by a stroke).
        /// </summary>
        /// <remarks>
        /// The range is where the head went of late, at most and at least, so
        /// that the oars of the picture follow the player whatever the size of
        /// their strokes.
        /// </remarks>
        public float Pull { get; private set; } = float.NaN;

        /// <summary>Whether we know home.</summary>
        public bool HasHome => !double.IsNaN(_homeX);

        private double _homeX = double.NaN;
        private double _lastSeen = double.NaN;

        // The stroke: whether the head goes down, and the highest and the lowest
        // point of the head (y grows downwards) since the last turn, in units.
        private bool _down;
        private float _top = float.NaN;
        private float _bottom = float.NaN;

        // The range of the head of late, for the pull (in units).
        private float _rangeTop = float.NaN;
        private float _rangeBottom = float.NaN;

        /// <summary>
        /// Observe the head of the player at the time <paramref name="t"/>, in
        /// frame pixels, with the unit of the player in frame pixels; pass NaN
        /// for the head if it was not seen. Return whether a stroke was counted.
        /// </summary>
        public bool Observe(double t, float headX, float headY, float unit)
        {
            if (float.IsNaN(headX) || float.IsNaN(headY) || float.IsNaN(unit) || unit <= 0f)
            {
                if (!double.IsNaN(_lastSeen) && t - _lastSeen > LoseAfter)
                {
                    Reset();
                }

                return false;
            }

            double dt = double.IsNaN(_lastSeen) ? 0.0 : Math.Clamp(t - _lastSeen, 0.0, 0.5);
            _lastSeen = t;

            float x = headX / unit;
            float y = headY / unit;

            if (double.IsNaN(_homeX))
            {
                _homeX = x;
            }

            Shift = (float)(_homeX - x);
            float away = Math.Abs(Shift);
            double follow = away < DeadZone ? HomeFollow : HomeDrift;
            _homeX += (x - _homeX) * (1.0 - Math.Exp(-dt / follow));

            Steer = Math.Sign(Shift) * Math.Clamp((away - DeadZone) / (FullSteer - DeadZone), 0f, 1f);

            ObserveRange(dt, y);

            if (away > SteeringFrom)
            {
                // NOTE (mristin):
                // Start afresh after the steering, so that coming back to home
                // does not count as a stroke.
                _top = float.NaN;
                _bottom = float.NaN;
                _down = false;
                return false;
            }

            return ObserveHeight(t, y);
        }

        private void ObserveRange(double dt, float y)
        {
            if (float.IsNaN(_rangeTop))
            {
                _rangeTop = y;
                _rangeBottom = y;
            }

            // NOTE (mristin):
            // The range takes in every new top and bottom at once, and lets go of
            // the old ones slowly.
            float relax = (float)(1.0 - Math.Exp(-dt / RangeMemory));
            _rangeTop = Math.Min(_rangeTop + (y - _rangeTop) * relax, y);
            _rangeBottom = Math.Max(_rangeBottom + (y - _rangeBottom) * relax, y);
            float range = _rangeBottom - _rangeTop;
            Pull = range >= StrokeDepth ? Math.Clamp((y - _rangeTop) / range, 0f, 1f) : float.NaN;
        }

        private bool ObserveHeight(double t, float y)
        {
            if (float.IsNaN(_top))
            {
                _top = y;
                _bottom = y;
                _down = false;
                return false;
            }

            if (!_down)
            {
                _top = Math.Min(_top, y);
                if (y - _top >= StrokeDepth)
                {
                    _down = true;
                    _bottom = y;
                }

                return false;
            }

            _bottom = Math.Max(_bottom, y);
            if (_bottom - y < StrokeDepth)
            {
                return false;
            }

            Strokes++;
            LastStrokeAt = t;
            LastStrokeDepth = _bottom - _top;
            _down = false;
            _top = y;
            return true;
        }

        /// <summary>Forget the player: home, the steering and the stroke under way (not the count).</summary>
        public void Reset()
        {
            _homeX = double.NaN;
            _lastSeen = double.NaN;
            _top = float.NaN;
            _bottom = float.NaN;
            _down = false;
            _rangeTop = float.NaN;
            _rangeBottom = float.NaN;
            Pull = float.NaN;
            Shift = 0f;
            Steer = 0f;
        }
    }
}  // namespace DrunkenVikings.Vision
