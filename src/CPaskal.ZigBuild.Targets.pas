{===============================================================================
  CPaskal™ Programming Language

  Copyright © 2026-present tinyBigGAMES™ LLC
  All Rights Reserved.

  https://cpaskal.org

  See LICENSE for license information
 -------------------------------------------------------------------------------
  CPaskal.ZigBuild.Targets - Supported target architectures, OSes, and ABIs.

  String constants for every architecture, operating system, and ABI that the
  bundled Zig/Clang toolchain supports. Use them with SetTarget to compose a
  target triple without memorizing exact tag spellings, e.g.
  SetTarget(ARCH_X86_64, OS_WINDOWS, ABI_MSVC). Raw triple strings work too;
  these constants are convenience and typo-safety, not a limit on what Zig
  accepts.

  GENERATED FILE - DO NOT EDIT BY HAND.
  Regenerate with _gentargets.cmd (runs `zig targets` and re-emits this unit).

  Dependencies: none
===============================================================================}

unit CPaskal.ZigBuild.Targets;

interface

const
  { Architectures }
  ARCH_AARCH64      = 'aarch64';
  ARCH_AARCH64_BE   = 'aarch64_be';
  ARCH_ALPHA        = 'alpha';
  ARCH_AMDGCN       = 'amdgcn';
  ARCH_ARC          = 'arc';
  ARCH_ARCEB        = 'arceb';
  ARCH_ARM          = 'arm';
  ARCH_ARMEB        = 'armeb';
  ARCH_AVR          = 'avr';
  ARCH_BPFEB        = 'bpfeb';
  ARCH_BPFEL        = 'bpfel';
  ARCH_CSKY         = 'csky';
  ARCH_EZ80         = 'ez80';
  ARCH_HEXAGON      = 'hexagon';
  ARCH_HPPA         = 'hppa';
  ARCH_HPPA64       = 'hppa64';
  ARCH_KALIMBA      = 'kalimba';
  ARCH_KVX          = 'kvx';
  ARCH_LANAI        = 'lanai';
  ARCH_LOONGARCH32  = 'loongarch32';
  ARCH_LOONGARCH64  = 'loongarch64';
  ARCH_M68K         = 'm68k';
  ARCH_M88K         = 'm88k';
  ARCH_MICROBLAZE   = 'microblaze';
  ARCH_MICROBLAZEEL = 'microblazeel';
  ARCH_MIPS         = 'mips';
  ARCH_MIPSEL       = 'mipsel';
  ARCH_MIPS64       = 'mips64';
  ARCH_MIPS64EL     = 'mips64el';
  ARCH_MSP430       = 'msp430';
  ARCH_NVPTX        = 'nvptx';
  ARCH_NVPTX64      = 'nvptx64';
  ARCH_OR1K         = 'or1k';
  ARCH_POWERPC      = 'powerpc';
  ARCH_POWERPCLE    = 'powerpcle';
  ARCH_POWERPC64    = 'powerpc64';
  ARCH_POWERPC64LE  = 'powerpc64le';
  ARCH_PROPELLER    = 'propeller';
  ARCH_RISCV32      = 'riscv32';
  ARCH_RISCV32BE    = 'riscv32be';
  ARCH_RISCV64      = 'riscv64';
  ARCH_RISCV64BE    = 'riscv64be';
  ARCH_S390X        = 's390x';
  ARCH_SH           = 'sh';
  ARCH_SHEB         = 'sheb';
  ARCH_SPARC        = 'sparc';
  ARCH_SPARC64      = 'sparc64';
  ARCH_SPIRV32      = 'spirv32';
  ARCH_SPIRV64      = 'spirv64';
  ARCH_THUMB        = 'thumb';
  ARCH_THUMBEB      = 'thumbeb';
  ARCH_VE           = 've';
  ARCH_WASM32       = 'wasm32';
  ARCH_WASM64       = 'wasm64';
  ARCH_X86_16       = 'x86_16';
  ARCH_X86          = 'x86';
  ARCH_X86_64       = 'x86_64';
  ARCH_XCORE        = 'xcore';
  ARCH_XTENSA       = 'xtensa';
  ARCH_XTENSAEB     = 'xtensaeb';

  { Operating Systems }
  OS_FREESTANDING = 'freestanding';
  OS_OTHER        = 'other';
  OS_CONTIKI      = 'contiki';
  OS_FUCHSIA      = 'fuchsia';
  OS_HERMIT       = 'hermit';
  OS_MANAGARM     = 'managarm';
  OS_HAIKU        = 'haiku';
  OS_HURD         = 'hurd';
  OS_ILLUMOS      = 'illumos';
  OS_LINUX        = 'linux';
  OS_PLAN9        = 'plan9';
  OS_RTEMS        = 'rtems';
  OS_SERENITY     = 'serenity';
  OS_DRAGONFLY    = 'dragonfly';
  OS_FREEBSD      = 'freebsd';
  OS_NETBSD       = 'netbsd';
  OS_OPENBSD      = 'openbsd';
  OS_DRIVERKIT    = 'driverkit';
  OS_IOS          = 'ios';
  OS_MACCATALYST  = 'maccatalyst';
  OS_MACOS        = 'macos';
  OS_TVOS         = 'tvos';
  OS_VISIONOS     = 'visionos';
  OS_WATCHOS      = 'watchos';
  OS_WINDOWS      = 'windows';
  OS_UEFI         = 'uefi';
  OS_3DS          = '3ds';
  OS_WIIU         = 'wiiu';
  OS_PSX          = 'psx';
  OS_PS3          = 'ps3';
  OS_PS4          = 'ps4';
  OS_PS5          = 'ps5';
  OS_PSP          = 'psp';
  OS_VITA         = 'vita';
  OS_EMSCRIPTEN   = 'emscripten';
  OS_WASI         = 'wasi';
  OS_AMDHSA       = 'amdhsa';
  OS_AMDPAL       = 'amdpal';
  OS_CUDA         = 'cuda';
  OS_MESA3D       = 'mesa3d';
  OS_NVCL         = 'nvcl';
  OS_OPENCL       = 'opencl';
  OS_OPENGL       = 'opengl';
  OS_VULKAN       = 'vulkan';
  OS_TIOS         = 'tios';

  { ABIs }
  ABI_NONE        = 'none';
  ABI_GNU         = 'gnu';
  ABI_GNUABIN32   = 'gnuabin32';
  ABI_GNUABI64    = 'gnuabi64';
  ABI_GNUEABI     = 'gnueabi';
  ABI_GNUEABIHF   = 'gnueabihf';
  ABI_GNUF32      = 'gnuf32';
  ABI_GNUSF       = 'gnusf';
  ABI_GNUX32      = 'gnux32';
  ABI_EABI        = 'eabi';
  ABI_EABIHF      = 'eabihf';
  ABI_ABIN32      = 'abin32';
  ABI_X32         = 'x32';
  ABI_ILP32       = 'ilp32';
  ABI_ANDROID     = 'android';
  ABI_ANDROIDEABI = 'androideabi';
  ABI_MUSL        = 'musl';
  ABI_MUSLABIN32  = 'muslabin32';
  ABI_MUSLABI64   = 'muslabi64';
  ABI_MUSLEABI    = 'musleabi';
  ABI_MUSLEABIHF  = 'musleabihf';
  ABI_MUSLF32     = 'muslf32';
  ABI_MUSLSF      = 'muslsf';
  ABI_MUSLX32     = 'muslx32';
  ABI_MSVC        = 'msvc';
  ABI_ITANIUM     = 'itanium';
  ABI_SIMULATOR   = 'simulator';
  ABI_OHOS        = 'ohos';
  ABI_OHOSEABI    = 'ohoseabi';
  ABI_CALL0       = 'call0';

implementation

end.
