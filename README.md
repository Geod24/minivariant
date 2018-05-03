# Minivariant: Simple, focused variant library

## Goal

Minivariant provides a simple way to work with a tagged union.
It aims to provide a replacement for `std.variant.Algebraic`, which is built on top of `std.variant.Variant`.

The issue that spawned this effort was the inability of `Algebraic` to work with basic type conversion,
e.g. it triggers a `static assert`ion failure to assign an `immutable int` to an `Algebraic` containing an `int`.

## Overview

The main type is `minivariant.variant.Variant`. It takes a tuple of accepted parameters:
```D
auto my_variant = Variant!(uint, char, bool, string)("Hello world");
```
It provides a pedestrian usage, via `isType` and `peek`, and a more structured approach via `visit`.
