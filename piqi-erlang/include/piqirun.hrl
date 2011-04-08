%% Copyright 2009, 2010, 2011 Anton Lavrik
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%
% Header file for Piqi Erlang Runitme library
%
-ifndef(__PIQIRUN_HRL__).
-define(__PIQIRUN_HRL__, 1).

% non_neg_integer() holds a value for all varint and zigzag_varint types:
%
%    bool, int, int32, int64, uint, uint32, uint64, proto-int32, proto-int64,
%    enum
%
% {fixed32, binary()} with a binary of size 4 holds a value for fixed32 -encoded
% types:
%    
%    int32-fixed, uint32-fixed, float32
%
% {fixed64, binary()} with a binary of size 8 holds a value for fixed64 -encoded
% types:
%    
%    int64-fixed, uint64-fixed, float64
%
% {block, binary()} represents a variable-length block which is used for
% encoding the following types:
%
%    binaries, strings, records, variants, lists
%
-type piqirun_return_buffer() ::
      non_neg_integer()
    | {'fixed32', binary()}
    | {'fixed64', binary()}
    | {'block', binary()}.


% binary() is the only allowed value type for top-level values and is not used
% in any other contexts
-type piqirun_buffer() :: piqirun_buffer() | binary().


% Wire field code which is used for identifying individual fields in binary
% record representation.
%
% If 'undefined' is used instead of integer code, no record header will be
% generated when calling `gen_<smth>` functions from Erlang module generated by
% `piqic erlang`. This mechanizm will only work with `list`, `record` and
% `variant` types.
%
% If 'undefined' value is specified when generating field values of primitive
% types such as `integer` or `string`, they will be generated with field tag
% `1`.
%
-type piqirun_code() :: 'undefined' | pos_integer().


-endif.