"""Read-only artwork audit; writes numeric JSON, never edits PNG pixels."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent
OLD = ROOT.parent / 'room-cats-2026-10-08'
standing = json.loads((OLD / 'idle-v2-contract.json').read_text())['poses'][0]
sleeping = json.loads((OLD / 'sleep-idle-v3-contract.json').read_text())['pose']

# Manually read paw-tip ground points from the original-resolution artwork.
# These are diagnostic observations with +/-8 source-pixel uncertainty, not
# accepted world anchors and never used to move/fit an asset into the room.
CASES = [
    ('standing-style-retry.png', standing,
     [[414, 624], [246, 687], [696, 711], [590, 779]],
     'Four visible paws. Old style reference geometry still dominates.'),
    ('standing-guide-retry.png', standing,
     [[425, 620], [311, 686], [680, 731], [539, 799]],
     'Far rear paw partly occluded; four guide contacts are not retained.'),
    ('sleeping-guide-retry.png', sleeping,
     [[801, 686], [649, 740]],
     'Closed eyes, two visible forepaws, but actual contacts depart from guide.'),
]

results = []
for filename, contract, observations, anatomy in CASES:
    file = ROOT / filename
    image = Image.open(file)
    if image.mode != 'RGBA':
        raise ValueError(f'{filename}: generated output must preserve RGBA')
    ratio = image.width / contract['canvas'][0]
    if not math.isclose(ratio, image.height / contract['canvas'][1]):
        raise ValueError(f'{filename}: atlas aspect ratio differs from guide')
    expected = [[x * ratio, y * ratio] for x, y in contract['contacts']]
    tolerance = 8 * ratio
    errors = [math.dist(actual, target)
              for actual, target in zip(observations, expected)]
    alpha = image.getchannel('A')
    histogram = alpha.histogram()
    # Count saturated colored *visible* pixels to distinguish transparent RGB
    # from an actual edge defect. Human light/night inspection is still needed.
    colored = [
        (x, y, a) for y in range(image.height) for x in range(image.width)
        for r, g, b, a in [image.getpixel((x, y))]
        if a >= 64 and r > 180 and b < 90 and (g < 70 or g > 220)
    ]
    results.append({
        'file': filename,
        'sha256': hashlib.sha256(file.read_bytes()).hexdigest(),
        'size': list(image.size), 'mode': image.mode,
        'guideScale': ratio, 'requestedToleranceSourcePixels': tolerance,
        'contactsExpected': expected,
        'contactsManuallyObserved': observations,
        'observationUncertaintySourcePixels': 8,
        'contactErrorSourcePixels': errors,
        'contactPassEvenWithObservationUncertainty': all(
            error <= tolerance + 8 for error in errors),
        'registrationFitApplied': False,
        'anatomyObservation': anatomy,
        'alpha': {
            'transparentPixels': histogram[0],
            'opaquePixels': histogram[255],
            'partiallyTransparentPixels': sum(histogram[1:255]),
            'nonzeroBounds': alpha.getbbox(),
            'visibleSaturatedRedOrYellowPixels': len(colored),
            'firstVisibleColorSamples': colored[:12],
        },
        'acceptedForNative': False,
    })

report = {
    'date': '2026-10-09', 'standard': 'room-standard-v1',
    'status': 'REJECTED_CONTACT_REGISTRATION',
    'method': 'Manual source-resolution paw observations compared with the '
              'pre-existing numerical guide. No ground search or fitted '
              'translation, shear, stretch, camera change, or PNG editing.',
    'footprintChanged': False,
    'nativeRoomVerified': False, 'phoneVerified': False,
    'originalAccountAccessed': False,
    'results': results,
}
(ROOT / 'inspection.json').write_text(
    json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({
    'status': report['status'],
    'cases': [{k: r[k] for k in
               ('file', 'contactErrorSourcePixels', 'acceptedForNative')}
              for r in results],
}, ensure_ascii=False))
