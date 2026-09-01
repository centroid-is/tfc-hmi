// Copyright (c) Centroid. Part of CentroidX.

#include "../video_geometry.h"

#include "test_support.h"

namespace {

using media_kit_video_elinux::FitWithinRenderBudget;
using media_kit_video_elinux::NotifiableSize;
using media_kit_video_elinux::ParseNullableInt;
using media_kit_video_elinux::PixelBufferBytes;
using media_kit_video_elinux::ResolveRenderSize;
using media_kit_video_elinux::Size;
using media_kit_video_elinux::StrideBytes;

TEST(ParsesAWholeNumber) {
  EXPECT_EQ(ParseNullableInt("1920").value_or(-1), 1920);
  EXPECT_EQ(ParseNullableInt("1").value_or(-1), 1);
}

TEST(ParsesTheLiteralNullAsNoOpinion) {
  EXPECT_TRUE(!ParseNullableInt("null").has_value());
}

TEST(RejectsEverythingThatIsNotAPositiveWholeNumber) {
  // A dimension that is not a size must degrade to "no opinion". Anything
  // else ends up as a stride or an allocation.
  EXPECT_TRUE(!ParseNullableInt("").has_value());
  EXPECT_TRUE(!ParseNullableInt("0").has_value());
  EXPECT_TRUE(!ParseNullableInt("-4").has_value());
  EXPECT_TRUE(!ParseNullableInt("12abc").has_value());
  EXPECT_TRUE(!ParseNullableInt(" 12").has_value());
  EXPECT_TRUE(!ParseNullableInt("12.0").has_value());
  EXPECT_TRUE(!ParseNullableInt("99999999999999999999").has_value());
}

TEST(LeavesASizeInsideTheBudgetAlone) {
  EXPECT_EQ(FitWithinRenderBudget({640, 480}), (Size{640, 480}));
  EXPECT_EQ(FitWithinRenderBudget({1920, 1080}), (Size{1920, 1080}));
}

TEST(ScalesAnOversizedFrameKeepingItsAspect) {
  EXPECT_EQ(FitWithinRenderBudget({3840, 2160}), (Size{1920, 1080}));
  // Wider than the budget but not taller: width is the binding constraint.
  EXPECT_EQ(FitWithinRenderBudget({3840, 1080}), (Size{1920, 540}));
  // Taller than the budget but not wider: height binds.
  EXPECT_EQ(FitWithinRenderBudget({1000, 2160}), (Size{500, 1080}));
}

TEST(NeverScalesADimensionAwayEntirely) {
  // An extreme aspect ratio must still render a strip, not a zero-width
  // texture that no renderer will accept.
  const Size fitted = FitWithinRenderBudget({4000, 1});
  EXPECT_EQ(fitted.width, 1920);
  EXPECT_EQ(fitted.height, 1);
}

TEST(AnEmptySizeStaysEmpty) {
  EXPECT_EQ(FitWithinRenderBudget({0, 0}), (Size{0, 0}));
  EXPECT_EQ(FitWithinRenderBudget({640, 0}), (Size{0, 0}));
  EXPECT_EQ(FitWithinRenderBudget({-8, 480}), (Size{0, 0}));
}

TEST(ARequestedSizeWinsOverTheVideosOwn) {
  EXPECT_EQ(ResolveRenderSize({320, 240}, {1920, 1080}), (Size{320, 240}));
}

TEST(APartialRequestIsNotASize) {
  // media_kit sends width and height separately; one of them alone says
  // nothing about the frame to render.
  EXPECT_EQ(ResolveRenderSize({320, 0}, {1920, 1080}), (Size{1920, 1080}));
  EXPECT_EQ(ResolveRenderSize({0, 240}, {1920, 1080}), (Size{1920, 1080}));
  EXPECT_EQ(ResolveRenderSize({0, 0}, {0, 0}), (Size{0, 0}));
}

TEST(ARequestedSizeIsStillHeldToTheBudget) {
  EXPECT_EQ(ResolveRenderSize({7680, 4320}, {640, 480}), (Size{1920, 1080}));
}

TEST(AnUnknownSizeIsReportedAsOneByOne) {
  // Reporting 0x0 would leave the `Texture` widget unlaid-out, and a texture
  // that Flutter never asks about never produces a frame.
  EXPECT_EQ(NotifiableSize({0, 0}), (Size{1, 1}));
  EXPECT_EQ(NotifiableSize({640, 0}), (Size{1, 1}));
  EXPECT_EQ(NotifiableSize({640, 480}), (Size{640, 480}));
}

TEST(DescribesTheBufferForASize) {
  EXPECT_EQ(StrideBytes({640, 480}), 2560);
  EXPECT_EQ(PixelBufferBytes({640, 480}), static_cast<size_t>(640 * 480 * 4));
  EXPECT_EQ(PixelBufferBytes({0, 0}), static_cast<size_t>(0));
}

}  // namespace
