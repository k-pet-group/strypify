from PIL import Image
import imagehash
import os

actual = os.environ['ACTUALFILE']
expected = os.environ['EXPECTEDFILE']

h1 = imagehash.phash(Image.open(expected))
h2 = imagehash.phash(Image.open(actual))

print("Hamming distance:", h1 - h2)

if (h1 - h2) < 25:
    print(f"Images are nearly identical {h1 - h2}")
else:
    raise Exception(f"Image is too different from expected (distance {h1 - h2})")
