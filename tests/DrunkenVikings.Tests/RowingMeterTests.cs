using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;

using DrunkenVikings.Vision;
using Xunit;

namespace DrunkenVikings.Tests
{
    public class RowingMeterTests
    {
        private record Sample(double T, float X, float Y, float Unit);

        private static List<Sample> LoadReplay(string name)
        {
            string path = Path.Combine(AppContext.BaseDirectory, "data", name);
            var samples = new List<Sample>();
            foreach (string line in File.ReadAllLines(path))
            {
                if (line.StartsWith("#") || line.StartsWith("t,") || string.IsNullOrWhiteSpace(line))
                {
                    continue;
                }

                var parts = line.Split(',');
                float Parse(string s) => s == "" ? float.NaN : float.Parse(s, CultureInfo.InvariantCulture);
                samples.Add(new Sample(
                    double.Parse(parts[0], CultureInfo.InvariantCulture), Parse(parts[1]), Parse(parts[2]), Parse(parts[3])));
            }

            return samples;
        }

        /// <summary>Replay the samples; return the times of the strokes and the steering at each time.</summary>
        private static (List<double> Strokes, List<(double T, float Steer)> Steering) Replay(
            RowingMeter meter, List<Sample> samples)
        {
            var strokes = new List<double>();
            var steering = new List<(double, float)>();
            foreach (var sample in samples)
            {
                if (meter.Observe(sample.T, sample.X, sample.Y, sample.Unit))
                {
                    strokes.Add(sample.T);
                }

                steering.Add((sample.T, meter.Steer));
            }

            return (strokes, steering);
        }

        [Fact]
        public void Counts_the_strokes_of_a_real_player_but_not_the_steering()
        {
            var (strokes, _) = Replay(new RowingMeter(), LoadReplay("free_rowing.csv"));

            int first = strokes.Count(t => t < 13.8);
            int steering = strokes.Count(t => t >= 13.8 && t < 25.5);
            int second = strokes.Count(t => t >= 25.5 && t < 47.5);

            // NOTE (mristin):
            // The player rowed 5 strokes, then steered, then rowed 8 strokes
            // (counted by hand on the plot of the head).
            Assert.Equal(5, first);
            Assert.Equal(0, steering);
            Assert.Equal(8, second);
        }

        [Fact]
        public void Steers_to_the_side_where_the_real_player_went()
        {
            var (_, steering) = Replay(new RowingMeter(), LoadReplay("free_rowing.csv"));

            float At(double t) => steering.OrderBy(s => Math.Abs(s.T - t)).First().Steer;

            Assert.Equal(-1f, At(15.2), 2);
            Assert.True(At(17.3) > 0.5f, $"Expected right at 17.3 s, but got {At(17.3)}");
            Assert.Equal(-1f, At(20.3), 2);
            Assert.True(At(22.8) > 0.5f, $"Expected right at 22.8 s, but got {At(22.8)}");

            // NOTE (mristin):
            // While rowing, the boat goes straight.
            Assert.All(steering.Where(s => s.T < 13.5 || (s.T > 26.0 && s.T < 47.0)), s => Assert.Equal(0f, s.Steer));
        }

        [Fact]
        public void Counts_a_synthetic_stroke_once()
        {
            var meter = new RowingMeter();
            int strokes = 0;
            for (int i = 0; i <= 60; i++)
            {
                double t = i / 20.0;
                float y = 300f + 80f * MathF.Sin((float)(2 * Math.PI * t / 3.0));
                strokes += meter.Observe(t, 320f, y, 100f) ? 1 : 0;
            }

            Assert.Equal(1, strokes);
            // NOTE (mristin):
            // The head goes down first, from the middle: the stroke is half the swing.
            Assert.Equal(0.8f, meter.LastStrokeDepth, 1);
        }

        [Fact]
        public void Going_to_the_players_right_steers_right()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f);

            // NOTE (mristin):
            // The frame is not mirrored: the player's right is towards the smaller x.
            meter.Observe(0.1, 220f, 210f, 100f);
            Assert.Equal(1f, meter.Shift, 2);
            Assert.Equal(1f, meter.Steer, 2);

            meter.Observe(0.2, 370f, 200f, 100f);
            Assert.True(meter.Steer < 0f && meter.Steer > -1f, $"Expected a slight left, but got {meter.Steer}");
        }

        [Fact]
        public void A_change_of_the_unit_does_not_steer()
        {
            // NOTE (mristin):
            // In the recording of the party (2026-11-23), the unit fell from 206
            // to 130 pixels while the head stayed; home was kept in units then,
            // and the boat spun while the player sat upright.
            var meter = new RowingMeter();
            for (int i = 0; i <= 40; i++)
            {
                meter.Observe(i / 10.0, 330f, 200f, 206f, 0f);
            }

            for (int i = 41; i <= 80; i++)
            {
                meter.Observe(i / 10.0, 330f, 200f, 130f, 0f);
                Assert.Equal(0f, meter.Steer);
            }
        }

        [Fact]
        public void Sitting_upright_after_a_long_lean_does_not_steer_the_other_way()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f, 0f);

            // NOTE (mristin):
            // Lean to the right slowly, and stay there for half a minute.
            double t = 0.0;
            for (int i = 1; i <= 30; i++)
            {
                t = i / 10.0;
                meter.Observe(t, 320f - 3.3f * i, 200f, 100f, 1f * i);
            }

            for (int i = 1; i <= 300; i++)
            {
                t += 0.1;
                meter.Observe(t, 220f, 200f, 100f, 30f);
            }

            Assert.True(meter.Steer > 0.9f, $"Expected right while leaning, but got {meter.Steer}");

            t += 0.1;
            meter.Observe(t, 320f, 200f, 100f, 0f);
            Assert.True(meter.Steer == 0f, $"Expected straight, but got {meter.Steer} (shift {meter.Shift}, tilt {meter.Tilt}, level {meter.Level})");
        }

        [Fact]
        public void Tilting_the_shoulders_steers_even_when_the_head_stays()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f, 0f);

            meter.Observe(0.1, 320f, 200f, 100f, 30f);
            Assert.Equal(1f, meter.Steer, 2);

            meter.Observe(0.2, 320f, 200f, 100f, -20f);
            Assert.Equal(-0.5f, meter.Steer, 1);
        }

        [Fact]
        public void The_head_and_the_shoulders_which_disagree_cancel_out()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f, 0f);

            // NOTE (mristin):
            // The head goes to the player's right, the shoulders to the left.
            meter.Observe(0.1, 220f, 200f, 100f, -30f);
            Assert.Equal(0f, meter.Steer, 2);
        }

        [Fact]
        public void Swapped_shoulders_do_not_steer()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f, 0f);
            meter.Observe(0.1, 320f, 200f, 100f, -166f);
            Assert.Equal(0f, meter.Steer);
            Assert.True(float.IsNaN(meter.Tilt));
        }

        [Fact]
        public void Home_follows_a_player_who_slid_on_the_seat()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f, 0f);

            // NOTE (mristin):
            // The head is a unit to the side, but the shoulders are level.
            double t = 0.0;
            for (int i = 1; i <= 400; i++)
            {
                t = i / 10.0;
                meter.Observe(t, 220f, 200f, 100f, 0f);
            }

            Assert.Equal(0f, meter.Steer);
        }

        [Fact]
        public void The_pull_follows_the_head_through_the_strokes()
        {
            var meter = new RowingMeter();
            float top = float.NaN;
            float bottom = float.NaN;
            for (int i = 0; i <= 200; i++)
            {
                double t = i / 20.0;
                float y = 300f + 40f * MathF.Sin((float)(2 * Math.PI * t / 2.5));
                meter.Observe(t, 320f, y, 100f);
                if (t > 5.0 && Math.Abs(t % 2.5 - 1.875) < 0.03)
                {
                    // NOTE (mristin):
                    // The head is at its top a quarter of a period before the start.
                    top = meter.Pull;
                }

                if (t > 5.0 && Math.Abs(t % 2.5 - 0.625) < 0.03)
                {
                    bottom = meter.Pull;
                }
            }

            Assert.True(top < 0.1f, $"Expected the oars forward at the top, but got {top}");
            Assert.True(bottom > 0.9f, $"Expected the pull done at the bottom, but got {bottom}");
        }

        [Fact]
        public void The_pull_follows_a_real_player_while_rowing()
        {
            var meter = new RowingMeter();
            int rowing = 0;
            int followed = 0;
            float lowest = 1f;
            float highest = 0f;
            foreach (var sample in LoadReplay("free_rowing.csv"))
            {
                meter.Observe(sample.T, sample.X, sample.Y, sample.Unit);
                bool rows = (sample.T > 3.0 && sample.T < 13.0) || (sample.T > 28.0 && sample.T < 46.0);
                if (!rows || float.IsNaN(sample.X))
                {
                    continue;
                }

                rowing++;
                if (!float.IsNaN(meter.Pull))
                {
                    followed++;
                    lowest = Math.Min(lowest, meter.Pull);
                    highest = Math.Max(highest, meter.Pull);
                }
            }

            Assert.True(followed > rowing * 0.95, $"Expected the oars to follow nearly always, but only {followed} of {rowing}");
            Assert.True(lowest < 0.05f && highest > 0.95f, $"Expected full strokes, but got {lowest} to {highest}");
        }

        [Fact]
        public void No_pull_while_the_player_sits_still()
        {
            var meter = new RowingMeter();
            for (int i = 0; i <= 100; i++)
            {
                meter.Observe(i / 20.0, 320f, 300f + (i % 2) * 2f, 100f);
            }

            Assert.True(float.IsNaN(meter.Pull));
        }

        [Fact]
        public void Forgets_the_player_who_left()
        {
            var meter = new RowingMeter();
            meter.Observe(0.0, 320f, 200f, 100f);
            Assert.True(meter.HasHome);
            meter.Observe(1.0, float.NaN, float.NaN, float.NaN);
            Assert.True(meter.HasHome);
            meter.Observe(3.5, float.NaN, float.NaN, float.NaN);
            Assert.False(meter.HasHome);
        }
    }
}
