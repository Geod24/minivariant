# Minivariant: Simple, focused variant library

## Goal

Minivariant provides a simple way to work with a tagged union.
It aims to provide a replacement for `std.variant.Algebraic`, which is built on top of `std.variant.Variant`.

The issue that spawned this effort was the inability of `Algebraic` to work with basic type conversion,
e.g. it triggers a `static assert`ion failure to assign an `immutable int` to an `Algebraic` containing an `int`.

## Overview

The main type is `geod24.variant : Variant`. It takes a tuple of accepted parameters:
```D
auto my_variant = Variant!(uint, char, bool, string)("Hello world");
```
It provides a pedestrian usage, via `isType` and `peek`, and a more structured approach via `visit`.

## Example

This is the "pedestrian" usage:
```d
@safe unittest
{
    // Default construction is forbidden
    // If you really need an empty Variant, use a dummy type
    auto variant = Variant!(uint, bool)(uint(42));
    // You can check the active type
    assert(variant.isType!uint);
    assert(!variant.isType!bool);
    // Even with types which are not part of the variant
    assert(!variant.isType!char);

    // You can peek a value
    if (auto valptr = variant.peek!uint)
        assert(*valptr == 42);
    if (auto valptr = variant.peek!bool)
        assert(0);
    if (auto valptr = variant.peek!int)
        assert(0);
}
```

The visit approach needs an externally constructed overload set,
so regular overloaded functions, either in a module or an aggregate are okay:
```d
public class ValueAsString
{
    import std.format;
    public static string opCall (T) (ref T value)
    {
        return format("%s %s", T.stringof, value);
    }
}

///
@safe unittest
{
    auto variant = Variant!(byte, char, string, bool)(byte(42));
    assert(variant.visit!ValueAsString == "byte 42");
    variant = true;
    assert(variant.visit!ValueAsString == "bool true");
    variant = "Hello World";
    assert(variant.visit!ValueAsString == "string Hello World");
}
```
