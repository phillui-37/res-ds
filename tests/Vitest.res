// Vitest.res — minimal bindings to the Vitest globals we actually use in tests.

@val external describe: (string, unit => unit) => unit = "describe"
@val external test: (string, unit => unit) => unit = "test"
@val external testAsync: (string, unit => promise<unit>) => unit = "test"

type expect<'a>
@val external expect: 'a => expect<'a> = "expect"
@send external toBe: (expect<'a>, 'a) => unit = "toBe"
@send external toEqual: (expect<'a>, 'a) => unit = "toEqual"
@send external toBeTruthy: expect<'a> => unit = "toBeTruthy"
@send external toBeFalsy: expect<'a> => unit = "toBeFalsy"
@send external toThrow: expect<unit => 'a> => unit = "toThrow"
@send external toThrowError: (expect<unit => 'a>, string) => unit = "toThrowError"

@get external not_: expect<'a> => expect<'a> = "not"
