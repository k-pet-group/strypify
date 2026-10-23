import os
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

# Compares a generated image with its reference. Run with ACTUALFILE and EXPECTEDFILE set; exits non-zero if
# they differ too much.
#
# This is a pixel comparison (after a slight blur, so that anti-aliasing noise does not matter), rather than a
# perceptual hash: a hash squashes the image to a tiny size so that it mostly sees the overall layout, which
# let a render of entirely the wrong project pass while a near-identical wide image could fail.
#
# The references are captured per platform (see expected/), because fonts render slightly differently on each.
# Calibration on real renders: the same example on Windows vs Linux differs by a mean of at most 0.5 (and under
# 0.1% strongly different pixels), a 1 pixel layout shift gives a mean around 1, a render of the wrong project
# gives a mean around 10 (with 8% strongly different pixels) and a capture of the whole editor around 47.
actual = os.environ['ACTUALFILE']
expected = os.environ['EXPECTEDFILE']

MAX_SIZE_DIFFERENCE = 2       # pixels, in each dimension
BLUR_RADIUS = 1.5
STRONG_DIFFERENCE = 40        # pixel difference (0-255) counted as "strongly different"
MAX_MEAN_DIFFERENCE = 1.0
MAX_STRONG_PERCENT = 0.5

a = Image.open(actual).convert('L')
e = Image.open(expected).convert('L')
print("Sizes actual/expected:", a.size, e.size)

if abs(a.width - e.width) > MAX_SIZE_DIFFERENCE or abs(a.height - e.height) > MAX_SIZE_DIFFERENCE:
    print(f"Image sizes differ by more than {MAX_SIZE_DIFFERENCE} pixels")
    sys.exit(1)

# Compare the part they have in common:
width, height = min(a.width, e.width), min(a.height, e.height)
a = a.crop((0, 0, width, height)).filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
e = e.crop((0, 0, width, height)).filter(ImageFilter.GaussianBlur(BLUR_RADIUS))
diff = ImageChops.difference(a, e)
mean = ImageStat.Stat(diff).mean[0]
strong_percent = 100 * sum(diff.histogram()[STRONG_DIFFERENCE:]) / (width * height)

print(f"Mean difference: {mean:.2f} (max {MAX_MEAN_DIFFERENCE}), strongly different pixels: "
      f"{strong_percent:.2f}% (max {MAX_STRONG_PERCENT}%)")

if mean <= MAX_MEAN_DIFFERENCE and strong_percent <= MAX_STRONG_PERCENT:
    print("Images match")
else:
    print("Images differ!")
    sys.exit(1)
