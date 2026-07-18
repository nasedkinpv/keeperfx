#include "tst_main.h"
#include "bflib_video.h"

ADD_TEST(test_good)
{
    CU_ASSERT(1);
}

ADD_TEST(test_good2)
{
    CU_ASSERT(2);
}

ADD_TEST(test_palette_tone_curve_preserves_black_and_hue)
{
    unsigned char palette[PALETTE_SIZE] = {0};
    palette[1] = 2;
    palette[3] = 32;
    palette[4] = 16;
    palette[5] = 8;

    CU_ASSERT_EQUAL(LbPaletteApplyToneCurve(palette, 4), Lb_SUCCESS);
    CU_ASSERT_EQUAL(palette[0], 0);
    CU_ASSERT_EQUAL(palette[1], 0);
    CU_ASSERT_EQUAL(palette[2], 0);
    CU_ASSERT_EQUAL(palette[3], 41);
    CU_ASSERT_EQUAL(palette[4], 21);
    CU_ASSERT_EQUAL(palette[5], 10);
}
