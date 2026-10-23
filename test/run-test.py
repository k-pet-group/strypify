import os
import sys

from PIL import Image, ImageChops, ImageFilter, ImageStat

# Compares a generated image with its reference. Run with ACTUALFILE and EXPECTEDFILE set; exits non-zero if
# they differ too much.
#
# This is a pixel comparison (after a slight blur, so that single-pixel anti-aliasing noise does not matter),
# rather than a perceptual hash: a hash squashes the image to a tiny size so that it mostly sees the overall
# layout, which let a render of entirely the wrong project pass while a near-identical wide image could fail.
#
# The references are captured per platform (see expected/), because fonts render differently on each (another
# platform's render can differ by 80+ in the worst patch below). On the same platform a render comes out
# identical to the pixel, so the limits only need to allow for a little slack.
#
# Two measures are used, because the mean over a large image would hide a small change (e.g. one changed
# character gives a mean of well under 0.1 on a tall image):
#  - the worst patch: the average difference within the most-different 16x16 block. Same platform: 0. A changed
#    character: 16 or more. A 1 pixel layout shift: around 20. The wrong project: around 95.
#  - the mean difference over the whole image, as a backstop for a widespread but faint change.
actual = os.environ['ACTUALFILE']
expected = os.environ['EXPECTEDFILE']

MAX_SIZE_DIFFERENCE = 2       # pixels, in each dimension
BLUR_RADIUS = 1.5
BLOCK_SIZE = 16               # pixels
MAX_WORST_PATCH = 10          # out of 255
MAX_MEAN_DIFFERENCE = 0.3     # out of 255

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
# Shrinking by box-averaging gives each block's mean difference, so the maximum is the worst patch:
blocks = diff.resize((max(1, width // BLOCK_SIZE), max(1, height // BLOCK_SIZE)), Image.BOX)
worst_patch = blocks.getextrema()[1]

print(f"Worst {BLOCK_SIZE}x{BLOCK_SIZE} patch difference: {worst_patch} (max {MAX_WORST_PATCH}), "
      f"mean difference: {mean:.2f} (max {MAX_MEAN_DIFFERENCE})")

if worst_patch <= MAX_WORST_PATCH and mean <= MAX_MEAN_DIFFERENCE:
    print("Images match")
else:
    print("Images differ!")
    sys.exit(1)
