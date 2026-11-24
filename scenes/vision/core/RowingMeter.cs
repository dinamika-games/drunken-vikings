using System;

// NOTE (mristin):
// The files in core/ must not depend on Godot so that we can unit-test the
// vision outside of the engine. See tests/DrunkenVikings.Tests.

namespace DrunkenVikings.Vision
{
    /// <summary>
    /// Turn the head and the shoulders of a player into the rowing: the
    /// strokes, and the steering.
    /// </summary>
    /// <remarks>
    /// <para>
    /// The player sits facing the camera. A stroke (leaning back and pulling,
    /// then reaching forward again) moves the head up and down in the picture by
    /// about three quarters of the unit; we count a stroke each time the head
    /// came back up by <see cref="StrokeDepth"/> after it went down as much.
    /// </para>
    /// <para>
    /// To steer, the player leans to the side with the whole upper body. We see
    /// the lean twice: the head goes to the side of home (where the head stays
    /// while the player rows, which we learn on the way), and the line of the
    /// shoulders tilts. The two agree when the player leans, so we steer by the
    /// stronger of them; when they disagree (e.g., the player only turns or
    /// tips the head), they cancel each other out. The tilt needs no home, so it
    /// steers right even when the head is lost or home is off.
    /// </para>
    /// <para>
    /// Home follows the head only while the shoulders are level: a player who
    /// leans keeps the home where it was, however long they lean, so that
    /// sitting upright again does not steer the other way. A player who slides
    /// on the seat keeps the shoulders level, and home follows them.
    /// </para>
    /// <para>
    /// While the player steers, the head goes down a little as well, so we
    /// count no strokes then: the player either rows, or glides and steers.
    /// </para>
    /// <para>
    /// The lengths are in the unit of the player (see <see cref="BodyScale"/>),
    /// but we keep the positions in frame pixels, so that a change of the unit
    /// (e.g., when the widest shoulders of late fall out of the window of the
    /// scale) does not move home. "Right" is the player's right: the frame is
    /// not mirrored, so the player's right is towards the smaller x. The
    /// instance is not thread-safe.
    /// </para>
    /// </remarks>
    public sealed class RowingMeter
    {
        /// <summary>The head must go down and back up by this much for a stroke, in units.</summary>
        public float StrokeDepth = 0.25f;

        /// <summary>No strokes count while the head is this far to the side, in units.</summary>
        public float SteeringFrom = 0.4f;

        /// <summary>The steering by the head starts this far to the side, in units.</summary>
        public float DeadZone = 0.3f;

        /// <summary>The steering by the head is full this far to the side, in units.</summary>
        public float FullSteer = 1.0f;

        /// <summary>The steering by the shoulders starts at this tilt from level, in degrees.</summary>
        public float TiltDeadZone = 10f;

        /// <summary>The steering by the shoulders is full at this tilt from level, in degrees.</summary>
        public float FullTilt = 30f;

        /// <summary>
        /// A tilt steeper than this, in degrees, is a mistake of the pose (e.g.,
        /// the shoulders swapped), and we take the shoulders as not seen.
        /// </summary>
        public float MaxTilt = 60f;

        /// <summary>Home follows the head within the dead zone with this time constant, in seconds.</summary>
        public double HomeFollow = 5.0;

        /// <summary>
        /// Home follows the head out of the dead zone with this time constant, in
        /// seconds, while the shoulders are level (the player moved on the seat).
        /// </summary>
        public double HomeSlide = 10.0;

        /// <summary>
        /// Home drifts towards the head out of the dead zone with this time
        /// constant, in seconds, while we do not see the shoulders.
        /// </summary>
        public double HomeDrift = 30.0;

        /// <summary>Level (the tilt of the shoulders when upright, e.g., the camera is askew) follows the tilt within the dead zone with this time constant, in seconds.</summary>
        public double LevelFollow = 5.0;

        /// <summary>
        /// Level drifts towards the tilt out of the dead zone with this time
        /// constant, in seconds, while the head is at home (e.g., the camera is
        /// askew); while the head is away as well, the player leans, and level
        /// stays.
        /// </summary>
        public double LevelDrift = 20.0;

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

        /// <summary>
        /// How far the shoulders tilt from level, in degrees, positive when the
        /// player leans to their right; NaN when we do not see the shoulders.
        /// </summary>
        public float Tilt { get; private set; } = float.NaN;

        /// <summary>The steering by the head alone, in [-1, 1].</summary>
        public float HeadSteer { get; private set; }

        /// <summary>The steering by the shoulders alone, in [-1, 1]; 0 when we do not see them.</summary>
        public float TiltSteer { get; private set; }

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

        /// <summary>Home, in frame pixels; NaN before the first head.</summary>
        public double HomeX => _homeX;

        /// <summary>Level: the tilt of the shoulders when the player sits upright, in degrees.</summary>
        public double Level => _level;

        private double _homeX = double.NaN;
        private double _level;
        private double _lastSeen = double.NaN;

        // The stroke: whether the head goes down, and the highest and the lowest
        // point of the head (y grows downwards) since the last turn, in pixels.
        private bool _down;
        private float _top = float.NaN;
        private float _bottom = float.NaN;

        // The range of the head of late, for the pull (in pixels).
        private float _rangeTop = float.NaN;
        private float _rangeBottom = float.NaN;

        /// <summary>
        /// Observe the head of the player at the time <paramref name="t"/>, in
        /// frame pixels, with the unit of the player in frame pixels and the
        /// tilt of the shoulders in degrees (see <see cref="RowingSignals.ShoulderTilt"/>);
        /// pass NaN for the head or the tilt if not seen. Return whether a stroke
        /// was counted.
        /// </summary>
        public bool Observe(double t, float headX, float headY, float unit, float shoulderTilt = float.NaN)
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

            if (double.IsNaN(_homeX))
            {
                _homeX = headX;
            }

            // NOTE (mristin):
            // Each of the head and the shoulders tells whether the other one
            // may follow: home follows the head while the shoulders are level,
            // and level follows the shoulders while the head is at home.
            Shift = (float)((_homeX - headX) / unit);
            float away = Math.Abs(Shift);
            bool inDeadZone = away < DeadZone;

            bool leans = false;
            if (float.IsNaN(shoulderTilt) || Math.Abs(shoulderTilt) > MaxTilt)
            {
                Tilt = float.NaN;
                TiltSteer = 0f;
            }
            else
            {
                Tilt = (float)(shoulderTilt - _level);
                float tiltAway = Math.Abs(Tilt);
                leans = tiltAway >= TiltDeadZone;
                double levelTime = !leans ? LevelFollow : inDeadZone ? LevelDrift : double.PositiveInfinity;
                _level += (shoulderTilt - _level) * Follow(dt, levelTime);
                TiltSteer = Math.Sign(Tilt) * Ramp(tiltAway, TiltDeadZone, FullTilt);
            }

            double homeTime =
                leans ? double.PositiveInfinity
                : inDeadZone ? HomeFollow
                : float.IsNaN(Tilt) ? HomeDrift
                : HomeSlide;
            _homeX += (headX - _homeX) * Follow(dt, homeTime);

            HeadSteer = Math.Sign(Shift) * Ramp(away, DeadZone, FullSteer);
            Steer = Combine(HeadSteer, TiltSteer);

            ObserveRange(dt, headY, unit);

            if (away > SteeringFrom || leans)
            {
                // NOTE (mristin):
                // Start afresh after the steering, so that coming back to home
                // does not count as a stroke.
                _top = float.NaN;
                _bottom = float.NaN;
                _down = false;
                return false;
            }

            return ObserveHeight(t, headY, unit);
        }

        /// <summary>The share by which to follow in <paramref name="dt"/> with the time constant <paramref name="tau"/>.</summary>
        private static double Follow(double dt, double tau) =>
            double.IsPositiveInfinity(tau) ? 0.0 : 1.0 - Math.Exp(-dt / tau);

        private static float Ramp(float value, float from, float full) =>
            Math.Clamp((value - from) / (full - from), 0f, 1f);

        /// <summary>
        /// Steer by the stronger of the head and the shoulders when they agree,
        /// and let them cancel each other out when they do not.
        /// </summary>
        private static float Combine(float head, float tilt)
        {
            if (Math.Sign(head) * Math.Sign(tilt) >= 0)
            {
                return Math.Abs(head) >= Math.Abs(tilt) ? head : tilt;
            }

            return Math.Clamp(head + tilt, -1f, 1f);
        }

        private void ObserveRange(double dt, float y, float unit)
        {
            if (float.IsNaN(_rangeTop))
            {
                _rangeTop = y;
                _rangeBottom = y;
            }

            // NOTE (mristin):
            // The range takes in every new top and bottom at once, and lets go of
            // the old ones slowly.
            float relax = (float)Follow(dt, RangeMemory);
            _rangeTop = Math.Min(_rangeTop + (y - _rangeTop) * relax, y);
            _rangeBottom = Math.Max(_rangeBottom + (y - _rangeBottom) * relax, y);
            float range = _rangeBottom - _rangeTop;
            Pull = range / unit >= StrokeDepth ? Math.Clamp((y - _rangeTop) / range, 0f, 1f) : float.NaN;
        }

        private bool ObserveHeight(double t, float y, float unit)
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
                if ((y - _top) / unit >= StrokeDepth)
                {
                    _down = true;
                    _bottom = y;
                }

                return false;
            }

            _bottom = Math.Max(_bottom, y);
            if ((_bottom - y) / unit < StrokeDepth)
            {
                return false;
            }

            Strokes++;
            LastStrokeAt = t;
            LastStrokeDepth = (_bottom - _top) / unit;
            _down = false;
            _top = y;
            return true;
        }

        /// <summary>Forget the player: home, the steering and the stroke under way (not the count).</summary>
        public void Reset()
        {
            _homeX = double.NaN;
            _level = 0.0;
            _lastSeen = double.NaN;
            _top = float.NaN;
            _bottom = float.NaN;
            _down = false;
            _rangeTop = float.NaN;
            _rangeBottom = float.NaN;
            Pull = float.NaN;
            Shift = 0f;
            Tilt = float.NaN;
            HeadSteer = 0f;
            TiltSteer = 0f;
            Steer = 0f;
        }
    }
}  // namespace DrunkenVikings.Vision
