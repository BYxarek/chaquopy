"""Package the Android libraries built by build_python_native_wheels.sh."""
import base64
import hashlib
from pathlib import Path
import struct
import sys
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

PACKAGES = (
    ("chaquopy_libxml2", "2.9.8", ("libxml2.so",), "MIT"),
    ("chaquopy_libxslt", "1.1.32", ("libxslt.so", "libexslt.so"), "MIT"),
    ("chaquopy_freetype", "2.9.1", ("libfreetype.so",), "FTL"),
    ("chaquopy_libjpeg", "1.5.3", ("libjpeg_chaquopy.so",), "IJG AND BSD-3-Clause AND Zlib"),
)


def check_elf(data):
    if data[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected Android ELF64")
    start = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    loads = [struct.unpack_from("<IIQQQQQQ", data, start + size * index) for index in range(count)]
    segments = [segment for segment in loads if segment[0] == 1]
    if not segments or any(p[7] < 16384 or (p[2] - p[3]) % 16384 for p in segments):
        raise ValueError("ELF load segments require 16 KiB alignment")


def build(abi, prefix, output):
    tag = f"py3-none-android_21_{abi}"
    for name, version, libraries, license_name in PACKAGES:
        info = f"{name}-{version}.dist-info"
        record = f"{info}/RECORD"
        source = {"chaquopy_libxml2": "libxml2-2.9.8/Copyright",
                  "chaquopy_libxslt": "libxslt-1.1.32/Copyright",
                  "chaquopy_freetype": "freetype-2.9.1/docs/FTL.TXT",
                  "chaquopy_libjpeg": "libjpeg-turbo-1.5.3/LICENSE.md"}
        files = {f"{info}/LICENSE": (prefix.parent / source[name]).read_bytes()}
        if name == "chaquopy_libjpeg":
            files[f"{info}/README.ijg"] = (prefix.parent / "libjpeg-turbo-1.5.3/README.ijg").read_bytes()
        for library in libraries:
            data = (prefix / "lib" / library).read_bytes()
            check_elf(data)
            files[f"chaquopy/lib/{library}"] = data
        files[f"{info}/METADATA"] = (f"Metadata-Version: 2.1\nName: {name.replace('_', '-')}\n"
                                     f"Version: {version}\nLicense: {license_name}\n").encode()
        files[f"{info}/WHEEL"] = f"Wheel-Version: 1.0\nRoot-Is-Purelib: false\nBuild: 9\nTag: {tag}\n".encode()
        rows = []
        for path, data in files.items():
            digest = base64.urlsafe_b64encode(hashlib.sha256(data).digest()).decode().rstrip("=")
            rows.append(f"{path},sha256={digest},{len(data)}")
        files[record] = ("\n".join([*rows, f"{record},,", ""])).encode()
        wheel = output / f"{name}-{version}-9-{tag}.whl"
        with ZipFile(wheel, "w") as archive:
            for path, data in files.items():
                archive.writestr(ZipInfo(path), data, compress_type=ZIP_DEFLATED)
        print(wheel)


if __name__ == "__main__":
    build(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))
