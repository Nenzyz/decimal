-module(decimal).

%% Converters
-export([
         to_decimal/2,
         to_binary/1
        ]).

%% Arith
-export([
         add/2,
         sub/2,
         mult/2,
         divide/3
        ]).

%% Compare
-export([
         cmp/3
        ]).

%% Utils
-export([
         abs/1,
         minus/1,
         reduce/1,
         round/3
        ]).

-type decimal() :: {integer(), integer()}.
-type rounding_algorithm() :: floor | ciel | half_up.
-type opts() :: #{
              precision => non_neg_integer(),
              rounding => rounding_algorithm()
           }.

-export_type([
              decimal/0,
              opts/0,
              rounding_algorithm/0
             ]).

%% =============================================================================
%%% API
%% =============================================================================

%% = Converters ================================================================

-spec to_decimal(Value, Opts) -> {ok, decimal()} | {error, Reason} when
      Value :: integer() | float() | binary() | list() | decimal(),
      Opts :: opts(),
      Reason :: any().
to_decimal({Int, E}=D, #{precision := Precision, rounding := Rounding}) when
      is_integer(Int), is_integer(E) ->
    Rounded = round(Rounding, D, Precision),
    {ok, Rounded};
to_decimal(Int, #{precision := Precision, rounding := Rounding}) when
      is_integer(Int) ->
    Rounded = round(Rounding, {Int, 0}, Precision),
    {ok, Rounded};
to_decimal(Binary, #{precision := Precision, rounding := Rounding}) when
      is_binary(Binary) ->
    case decimal_conv:from_binary(Binary) of
        {ok, Decimal} ->
            {ok, round(Rounding, Decimal, Precision)};
        {error, _Reason} = Err -> Err
    end;
to_decimal(Float, Opts) when
      is_float(Float) ->
    Bin = float_to_binary(Float),
    to_decimal(Bin, Opts);
to_decimal(List, Opts) ->
    Bin = list_to_binary(List),
    to_decimal(Bin, Opts).

-spec to_binary(decimal()) -> binary().
to_binary(Decimal) ->
    decimal_conv:to_binary(Decimal).

%% = Arith =====================================================================

-spec add(decimal(), decimal()) -> decimal().
add({Int1, E1}, {Int2, E2}) ->
    Emin = min(E1, E2),
    {Int1 * pow_of_ten(E1 - Emin) +
     Int2 * pow_of_ten(E2 - Emin),
     Emin}.

-spec sub(decimal(), decimal()) -> decimal().
sub(A, B) ->
    add(A, minus(B)).

-spec mult(decimal(), decimal()) -> decimal().
mult({Int1, E1}, {Int2, E2}) ->
    {Int1*Int2, E1+E2}.

-spec divide(decimal(), decimal(), opts()) -> decimal().
divide(A, B, #{ precision := Precision, rounding := Rounding }) ->
    {Int1, E1} = round(Rounding, A, Precision),
    {Int2, E2} = round(Rounding, B, Precision),
    case is_zero(B) of
        true -> error(badarith);
        _ ->
            Emin = min(E1, E2),
            Int =
                (Int1*pow_of_ten(E1-Emin+Precision+1)) div
                (Int2*pow_of_ten(E2-Emin)),
            round(Rounding, {Int, -Precision-1}, Precision)
    end.

%% = Compare ===================================================================

-spec cmp(decimal(), decimal(), opts()) -> -1 | 0 | 1.
cmp(A, B, #{ precision := Precision, rounding := Rounding }) ->
    {Int1, E1} = round(Rounding, A, Precision),
    {Int2, E2} = round(Rounding, B, Precision),

    Emin = min(E1, E2),
    B1 = Int1*pow_of_ten(E1-Emin),
    B2 = Int2*pow_of_ten(E2-Emin),
    if B1 =:= B2 -> 0;
       B1 < B2 -> -1;
       B1 > B2 -> 1
    end.

%% = Utils =====================================================================

is_zero({0, _}) -> true;
is_zero(_) -> false.

-spec minus(decimal()) -> decimal().
minus({Int, E}) ->
    {-Int, E}.

-spec abs(decimal()) -> decimal().
abs({Int, E}) ->
    {erlang:abs(Int), E}.

-spec reduce(decimal()) -> decimal().
reduce({Int, E}) ->
    reduce_(Int, E).
reduce_(0, _E) -> {0, 0};
reduce_(Int, E) ->
    case Int rem 10 of
        0 -> reduce_(Int div 10, E+1);
        _ -> {Int, E}
    end.

-spec round(rounding_algorithm(), decimal(), non_neg_integer()) -> decimal().
round(Rounding, Decimal, Precision) ->
    {Int, E} = Rounded = reduce(Decimal),
    case -Precision-E of
        Delta when Delta > 0 ->
            round_(Rounding, Int, E, Delta);
        _ ->
            Rounded
    end.
round_(floor, Int, E, Delta) ->
    P = pow_of_ten(Delta),
    {Int div P, E+Delta};
round_(Rounding, Int, E, Delta) when
      Rounding =:= half_up;
      Rounding =:= ciel ->
    P = pow_of_ten(Delta-1),
    Data = Int div P,
    Floor = Data div 10,
    LastDigit = Data-(Floor*10),
    Base =
        case Rounding of
            half_up when LastDigit >= 5 -> Floor+1;
            ciel when LastDigit > 0 -> Floor+1;
            _ -> Floor
        end,
    {Base, E+Delta}.

%% =============================================================================
%%% Internal functions
%% =============================================================================

-spec pow_of_ten(non_neg_integer()) -> pos_integer().
pow_of_ten(N) ->
    binary_to_integer(<<$1, (binary:copy(<<$0>>, N))/binary>>).
