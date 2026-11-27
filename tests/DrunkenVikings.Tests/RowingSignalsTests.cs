using System;
using System.Collections.Generic;

using DrunkenVikings.Vision;
using Xunit;

namespace DrunkenVikings.Tests
{
    public class RowingSignalsTests
    {
        private const float Threshold = 0.3f;

        /// <summary>
        /// A player sitting upright and facing the camera, with the hands in
        /// front of the chest; in the frame, which is not mirrored, the player's
        /// right is on the left.
        /// </summary>
        private static Dictionary<BodyPart, (float X, float Y)> Upright() => new()
        {
            [BodyPart.Nose] = (320, 150),
            [BodyPart.LeftEye] = (330, 140),
            [BodyPart.RightEye] = (310, 140),
            [BodyPart.LeftEar] = (345, 145),
            [BodyPart.RightEar] = (295, 145),
            [BodyPart.LeftShoulder] = (360, 200),
            [BodyPart.RightShoulder] = (280, 200),
            [BodyPart.LeftElbow] = (370, 260),
            [BodyPart.RightElbow] = (270, 260),
            [BodyPart.LeftWrist] = (340, 240),
            [BodyPart.RightWrist] = (300, 240),
            [BodyPart.LeftHip] = (350, 320),
            [BodyPart.RightHip] = (290, 320),
            [BodyPart.LeftKnee] = (360, 300),
            [BodyPart.RightKnee] = (280, 300),
            [BodyPart.LeftAnkle] = (360, 400),
            [BodyPart.RightAnkle] = (280, 400),
        };

        private static Pose MakePose(Dictionary<BodyPart, (float X, float Y)> points, params BodyPart[] missing)
        {
            var keypoints = new Keypoint[Pose.KeypointCount];
            foreach (var (part, point) in points)
            {
                float score = Array.IndexOf(missing, part) >= 0 ? 0.1f : 0.9f;
                keypoints[(int)part] = new Keypoint(point.X, point.Y, score);
            }

            return new Pose(keypoints, new BoundingBox(270, 140, 370, 400), 0.9f);
        }

        private static RowingSignals Measure(Pose pose) => RowingSignals.Measure(pose, 80f, 480, Threshold);

        [Fact]
        public void Measures_an_upright_player()
        {
            var signals = Measure(MakePose(Upright()));

            Assert.Equal(80f, signals.Unit);
            Assert.Equal(1.5f, signals.TorsoUp, 3);
            Assert.Equal(0f, signals.TorsoLean, 3);
            Assert.Equal(0f, signals.ShoulderTilt, 3);
            Assert.Equal(1f, signals.ShoulderWidth, 3);
            Assert.Equal(0f, signals.ShoulderShift, 3);
            Assert.Equal(0f, signals.HandsSide, 3);
            Assert.Equal(0f, signals.HeadSide, 3);
            Assert.Equal(-0.5f, signals.HandsUp, 3);
            Assert.Equal(0.5f, signals.HandSpread, 3);
            Assert.Equal(1.25f, signals.ElbowSpread, 3);
            Assert.Equal(200f / 480f, signals.ShoulderY, 3);
        }

        [Fact]
        public void Hands_to_the_players_right_are_positive()
        {
            var points = Upright();
            points[BodyPart.LeftWrist] = (280, 240);
            points[BodyPart.RightWrist] = (240, 240);

            Assert.Equal(0.75f, Measure(MakePose(points)).HandsSide, 3);
        }

        [Fact]
        public void Leaning_to_the_players_right_is_positive()
        {
            var points = Upright();
            foreach (var part in new[] { BodyPart.LeftShoulder, BodyPart.RightShoulder, BodyPart.Nose })
            {
                points[part] = (points[part].X - 40, points[part].Y);
            }

            // NOTE (mristin):
            // The right shoulder goes down as the player leans to the right.
            points[BodyPart.RightShoulder] = (points[BodyPart.RightShoulder].X, 220);

            var signals = Measure(MakePose(points));
            Assert.True(signals.TorsoLean > 10f, $"Expected a lean to the right, but got {signals.TorsoLean}");
            Assert.True(signals.ShoulderTilt > 10f, $"Expected a tilt to the right, but got {signals.ShoulderTilt}");
            Assert.Equal(0.5f, signals.ShoulderShift, 3);
        }

        [Fact]
        public void Leaning_back_shortens_the_torso()
        {
            var points = Upright();
            foreach (var part in new[] { BodyPart.LeftShoulder, BodyPart.RightShoulder, BodyPart.Nose })
            {
                points[part] = (points[part].X, points[part].Y + 40);
            }

            var upright = Measure(MakePose(Upright()));
            var back = Measure(MakePose(points));
            Assert.Equal(1f, back.TorsoUp, 3);
            Assert.True(back.HeadY > upright.HeadY);
        }

        [Fact]
        public void Turning_the_head_to_the_players_right_is_positive()
        {
            var points = Upright();
            points[BodyPart.Nose] = (300, 150);

            Assert.Equal(0.25f, Measure(MakePose(points)).HeadSide, 3);
        }

        [Fact]
        public void Without_the_hips_only_the_signals_of_the_upper_body_are_known()
        {
            var signals = Measure(MakePose(Upright(), BodyPart.LeftHip, BodyPart.RightHip));

            Assert.True(float.IsNaN(signals.TorsoUp));
            Assert.True(float.IsNaN(signals.TorsoLean));
            Assert.True(float.IsNaN(signals.HeadUp));
            Assert.True(float.IsNaN(signals.ShoulderShift));
            Assert.False(float.IsNaN(signals.HeadY));
            Assert.False(float.IsNaN(signals.HandsUp));

            // NOTE (mristin):
            // The hands are measured against the shoulders then.
            Assert.Equal(0f, signals.HandsSide, 3);
        }

        [Fact]
        public void Without_a_pose_all_the_signals_are_unknown()
        {
            foreach (float value in RowingSignals.Unknown.ToArray())
            {
                Assert.True(float.IsNaN(value));
            }

            Assert.Equal(RowingSignals.Names.Length, RowingSignals.Unknown.ToArray().Length);
        }
    }

    public class BodyScaleTests
    {
        private static Pose WithShoulders(float width)
        {
            var keypoints = new Keypoint[Pose.KeypointCount];
            keypoints[(int)BodyPart.LeftShoulder] = new Keypoint(320 + width / 2, 200, 0.9f);
            keypoints[(int)BodyPart.RightShoulder] = new Keypoint(320 - width / 2, 200, 0.9f);
            return new Pose(keypoints, new BoundingBox(0, 0, 1, 1), 0.9f);
        }

        [Fact]
        public void Keeps_the_widest_shoulders_through_a_twist()
        {
            var scale = new BodyScale { Window = 4.0 };
            Assert.Equal(80f, scale.Observe(0.0, WithShoulders(80), 0.3f), 3);
            Assert.Equal(80f, scale.Observe(1.0, WithShoulders(50), 0.3f), 3);
            Assert.Equal(80f, scale.Observe(2.0, null, 0.3f), 3);

            // NOTE (mristin):
            // Once the wide shoulders are older than the window, the unit follows
            // the narrower ones: the player moved away from the camera.
            Assert.Equal(50f, scale.Observe(4.5, WithShoulders(40), 0.3f), 3);
            Assert.Equal(40f, scale.Observe(5.5, WithShoulders(40), 0.3f), 3);
        }
    }
}
