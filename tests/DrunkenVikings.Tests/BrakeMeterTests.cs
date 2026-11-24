using DrunkenVikings.Vision;
using Xunit;

namespace DrunkenVikings.Tests
{
    public class BrakeMeterTests
    {
        private const float Nan = float.NaN;

        // NOTE (mristin):
        // The head at y = 200, the shoulders at 300, the unit 100 pixels.
        private static bool Observe(BrakeMeter meter, double t, float leftWrist, float rightWrist,
            float leftElbow = 350f, float rightElbow = 350f) =>
            meter.Observe(t, 200f, leftWrist, rightWrist, leftElbow, rightElbow, 300f, 300f, 100f);

        [Fact]
        public void Both_hands_high_above_the_head_brake()
        {
            var meter = new BrakeMeter();
            Assert.False(Observe(meter, 0.0, 400f, 400f));
            Assert.True(Observe(meter, 0.1, 150f, 160f));
        }

        [Fact]
        public void One_hand_up_does_not_brake()
        {
            var meter = new BrakeMeter();
            Assert.False(Observe(meter, 0.0, 120f, 400f));
        }

        [Fact]
        public void Hands_at_the_head_do_not_brake_but_keep_the_brake()
        {
            var meter = new BrakeMeter();
            Assert.False(Observe(meter, 0.0, 190f, 190f));
            Assert.True(Observe(meter, 0.1, 150f, 150f));
            Assert.True(Observe(meter, 0.2, 190f, 190f));
            Assert.False(Observe(meter, 0.3, 230f, 190f));
        }

        [Fact]
        public void Raised_elbows_count_while_the_hands_left_the_picture()
        {
            var meter = new BrakeMeter();
            Assert.True(Observe(meter, 0.0, Nan, Nan, 220f, 230f));
            Assert.False(Observe(meter, 0.1, Nan, Nan, 320f, 230f));
        }

        [Fact]
        public void Arms_out_of_sight_keep_the_brake_for_a_while()
        {
            var meter = new BrakeMeter();
            Assert.True(Observe(meter, 0.0, 150f, 150f));
            Assert.True(Observe(meter, 0.3, Nan, Nan, Nan, Nan));
            Assert.False(Observe(meter, 0.6, Nan, Nan, Nan, Nan));
        }
    }
}
