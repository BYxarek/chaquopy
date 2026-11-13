# Android 16 KiB dependency wheels for CPython 3.11

Builds the native dependencies used by Chaquopy Pillow 11.0.0 and lxml 5.3.0 for arm64-v8a and x86_64. The Python extension wheels already have 16 KiB ELF segments.

Use Linux x86_64, Android NDK r27c, Python 3, Make, Autoconf, Automake and Libtool.

```sh
bash server/pypi/bygram-16k/build_python_native_wheels.sh /path/to/android-ndk-r27c /path/to/work
```

The output directory contains eight Android wheels. Use pip --find-links with that directory. The script checks the pinned source archives and each ELF load segment, and embeds upstream license notices in the wheels.
