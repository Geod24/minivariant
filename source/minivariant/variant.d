/*******************************************************************************

    Minimalistic variant implementation  to work around `std.variant`'s quirks

    After 2 minutes of `std.variant`, it proved not useful for AltereD's needs,
    as we had the following code:

    ---
    alias ValueT = Variant!(byte, ubyte, short, ushort, int, uint, long, ulong);
    public void someCtor (ValueT value) {}
    static immutable int[4] Sizeof = [ 1, 2, 4, 8 ];
    someCtor(ValueT(Sizeof[2]));

    // The error triggered:
    // std/variant.d(590): Error: static assert  "Cannot store a
    // immutable(ubyte) in a VariantN!(8LU, byte, ubyte, short, ushort, int,
    // uint, long, ulong). Valid types are (byte, ubyte, short, ushort, int,
    // uint, long, ulong)"
    ---

    All we need is a union and static dispatch.
    This follows AltereD's approach to metaprogramming, where as much work
    is left to the compiler as possible, to avoid complicated and costly
    reimplementation of type semantics.

    Copyright: Copyright (c) 2016-2018 Mathias Lang. All rights reserved

    License: MIT (see LICENSE for details)

*******************************************************************************/

module minivariant.variant;

import std.meta : staticIndexOf;
import std.traits : isAssignable;


/// Ditto
public struct Variant (T...)
{
    /// Allowed types
    public alias Types = T;

    private union Union { Types data; }
    private Union _data;
    private size_t index;

    /// isAssignable has a default value so we cannot partially instantiate it
    private alias Assignable (X, Y) = isAssignable!(Y, X);
    /// Evaluates to `true` if a type can be stored in this variable
    public alias IsAllowed(X) = anySatisfy!(Assignable!(X), Types);

    /// Makes code simpler
    @disable this();

    /// As we cannot mix constructors in, this just forwards to the correct
    /// overload or errors out
    public this (T) (T value)
    {
        static if (is(typeof(this.constructor(value))))
            this.constructor(value);
        else
            static assert(0, "Cannot instantiate a " ~ typeof(this).stringof
                          ~ " from a " ~ T.stringof);
    }

    /// Returns:
    ///     `true` if type `TestedT` is currently the active type.
    public bool isType (TestedT) () const
    {
        // Workaround for 'statement is not reachable'
        bool hack;
        foreach (idx, T; typeof(Union.tupleof))
            static if (is(T == TestedT))
                if (!hack)
                    return idx == this.index;
        return false;
    }

    /// Returns:
    ///    A pointer to a value of type `TestedT`,
    ///    `null` if it's not the active type
    public TestedT* peek (TestedT) ()
    {
        // Workaround for 'statement is not reachable'
        bool hack;
        foreach (idx, T; typeof(Union.tupleof))
            static if (is(T == TestedT))
            {
                if (idx != this.index)
                    return null;
                if (!hack)
                    return &this._data.tupleof[idx];
            }
        return null;
    }

    /// Instead of 'patching' the type as `std.variant` does,
    /// we generate different overloads to take advantage of the compiler's
    /// resolution mecanism
    mixin ForeachInst!(GenCtor, "constructor", Types);
    /// Ditto
    mixin ForeachInst!(GenOpAssign, "opAssign", Types);
}

/// Pedestrian usage
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

/*******************************************************************************

    Allow to use a visitor-style approach with Variant

    When dealing with `Variant`, the simplest and default approach is to handle
    all types manually. For example, if a `Variant` hold a byte and a bool,
    one would naively use:
    ---
    auto variant = Variant!(bool, byte)(false);
    if (byte* val = variant.peek!byte)
        writeln("It's a byte: ", *val);
    else if (bool* val = variant.peek!bool)
        writeln("It's a bool: ", *val);
    ---

    However this doesn't scale well: It leads to a lot of code duplication,
    repetitive checks can be expensive and is usually not nice to play with.

    `visit` offers an alternative by accepting a `HandlerT`,
    which serves as a namespace for the handlers function to use.

    There are two possible overloads:
        - One for contextless handlers, that is, functions, `class` or `struct`
          with a `static opCall`
        - One for handlers with a context. It's mostly `struct` or `class`
          with an `opCall`.

    The former takes a template argument and the variant as runtime parameter,
    the later takes two runtime parameters.

*******************************************************************************/

public template visit (alias HandlerT)
{
    public auto visit (VariantT) (ref VariantT variant)
        if (is(VariantT : Variant!(Args), Args...))
    {
        switch (variant.index)
        {
            foreach (idx, TArg; VariantT.Types)
            {
            case idx:
                return HandlerT(variant._data.tupleof[idx]);
            }
        default:
            assert(0, "Unhandled index case");
        }
    }

    // Non-ref overload
    public auto visit (VariantT) (VariantT variant)
        if (is(VariantT : Variant!(Args), Args...))
    {
        switch (variant.index)
        {
            foreach (idx, TArg; VariantT.Types)
            {
            case idx:
                return HandlerT(variant._data.tupleof[idx]);
            }
        default:
            assert(0, "Unhandled index case");
        }
    }

}

/// Ditto
public auto visit (VariantT, HandlerT) (ref VariantT variant, HandlerT h)
    if (is(VariantT : Variant!(Args), Args...))
{
    switch (variant.index)
    {
        foreach (idx, TArg; VariantT.Types)
        {
        case idx:
            return h(variant._data.tupleof[idx]);
        }
    default:
        assert(0, "Unhandled index case");
    }
}

/// Ditto, non ref overload
public auto visit (VariantT, HandlerT) (VariantT variant, HandlerT h)
    if (is(VariantT : Variant!(Args), Args...))
{
    switch (variant.index)
    {
        foreach (idx, TArg; VariantT.Types)
        {
        case idx:
            return h(variant._data.tupleof[idx]);
        }
    default:
        assert(0, "Unhandled index case");
    }
}


version (unittest)
{
    // An overload set is an handler
    private void overloadset (byte v) @safe nothrow @nogc pure { assert(v == 42); }
    private void overloadset (char v) @safe nothrow @nogc pure { assert(v == '4'); }
}

///
@safe nothrow @nogc pure unittest
{
    // And so is a namespace: templates can be used
    static class HandlerC {
    static:
        void opCall (T) (T v) { assert(v == T.init); }
    }

    // Irrelevant overloads are not a problem
    static struct HandlerS {
    static:
        void opCall (byte v) { assert(v == 42); }
        void opCall (char v) { assert(v == '4'); }
        void opCall (uint v) { assert(0); }
        void opCall ()       { assert(0); }
    }

    auto variant = Variant!(byte, char)(byte(42));
    variant.visit!overloadset;
    variant.visit!HandlerS;
    variant = '4';
    variant.visit!HandlerS;
    variant.visit!overloadset;

    variant = char.init;
    variant.visit!HandlerC;
    variant = byte.init;
    variant.visit!HandlerC;
}

/// Predicate passed to ForeachInst to generate the constructor method
/// We cannot cleanly merge ctor overload set, so we have a template ctor that
/// will forward to this method
private mixin template GenCtor (T)
{
    private void constructor (T v)
    {
        immutable idx = staticIndexOf!(T, Types);
        this.index = idx;
        this._data.tupleof[idx] = v;
    }
}

/// Predicate passed to ForeachInst to generate opAssign
private mixin template GenOpAssign (T)
{
    public ref typeof(this) opAssign (T v)
    {
        immutable idx = staticIndexOf!(T, Types);
        this.index = idx;
        // TODO: Destruct the previous instance ?
        this._data.tupleof[idx] = v;
        return this;
    }
}


/// Utility class to get a string from a `Variant`
public class ValueAsString
{
    import std.format;

    public static string opCall (T) (ref T value)
    {
        return format("%s", value);
    }
}

///
@safe pure unittest
{
    auto variant = Variant!(byte, char, string, bool)(byte(42));
    assert(variant.visit!ValueAsString == "42");
    variant = true;
    assert(variant.visit!ValueAsString == "true");
    variant = "Hello World";
    assert(variant.visit!ValueAsString == "Hello World");
}

/*******************************************************************************

    Applies a template predicate to a list of arguments and merge the generated
    overload set.

    This template is explicitly designed to generate function definitions within
    a scope and add them to an overload set.
    The use of `sym` is necessary because overload sets from mixed-in templates
    are not merged in the parent.

    Params:
        Pred = Predicate to generate one of more functions named `sym`
        sym  = Name of the symbol to merge into an overload set
        Args = Arguments to instantiate `Pred` with

*******************************************************************************/

private template ForeachInst (alias Pred, string sym, Args...)
{
    static if (Args.length >= 1)
    {
        mixin Pred!(Args[0]) A0;
        mixin("alias " ~ sym ~ " = A0." ~ sym ~ ";");
    }
    static if (Args.length >= 2)
    {
        mixin Pred!(Args[1]) A1;
        mixin("alias " ~ sym ~ " = A1." ~ sym ~ ";");
    }
    static if (Args.length >= 3)
    {
        mixin Pred!(Args[2]) A2;
        mixin("alias " ~ sym ~ " = A2." ~ sym ~ ";");
    }
    static if (Args.length >= 4)
    {
        mixin Pred!(Args[3]) A3;
        mixin("alias " ~ sym ~ " = A3." ~ sym ~ ";");
    }
    static if (Args.length >= 5)
    {
        mixin Pred!(Args[4]) A4;
        mixin("alias " ~ sym ~ " = A4." ~ sym ~ ";");
    }
    static if (Args.length >= 6)
    {
        mixin Pred!(Args[5]) A5;
        mixin("alias " ~ sym ~ " = A5." ~ sym ~ ";");
    }
    static if (Args.length >= 7)
    {
        mixin Pred!(Args[6]) A6;
        mixin("alias " ~ sym ~ " = A6." ~ sym ~ ";");
    }
    static if (Args.length > 7)
    {
        mixin ForeachInst!(Pred, sym, Args[7 .. $]) Unrolled;
        mixin("alias " ~ sym ~ " = Unrolled." ~ sym ~ ";");
    }
}
