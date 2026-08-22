# Package
version       = "0.1.0"
author        = "Jonas Andersson, Claude (Anthropic)"
description   = "Arena-allocated context store for static site generators"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks

task bench, "Run performance benchmarks":
  exec "nim c -r -d:release --mm:orc --hints:off --warnings:off bench/bench.nim"
