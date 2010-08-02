(*pp camlp4o -I $PIQI_ROOT/camlp4 pa_labelscope.cmo pa_openin.cmo *)
(*
   Copyright 2009, 2010 Anton Lavrik

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)


module C = Piqi_common
open C


module R = Piqobj.Record
module F = Piqobj.Field
module V = Piqobj.Variant
module E = Piqobj.Variant
module O = Piqobj.Option
module A = Piqobj.Alias
module Any = Piqobj.Any
module L = Piqobj.List


(* NOTE: loosing precision here, in future we will support encoding floats as
 * string literals containing binary representation of 64-bit IEEE float *)
let gen_float x = `float x


let is_ascii_string s =
  let len = String.length s in
  let rec aux i =
    if i >= len
    then true
    else
      if Char.code s.[i] <= 127
      then aux (i + 1)
      else false
  in
  aux 0


let gen_string s =
  if is_ascii_string s
  then
    `ascii_string s
  else
    `utf8_string s


let gen_binary s =
  if is_ascii_string s
  then
    `ascii_string s
  else
    `binary s


let gen_any x =
  open Any in
  (* XXX: is it always defined? *)

  (* TODO: handle typed *)
  some_of x.any.T.Any.ast


let make_named name value =
  open T in
  `named Named#{name = name; value = value}


let make_name name =
  `name name


let rec gen_obj0 (x:Piqobj.obj) :T.ast =
  match x with
    (* built-in types *)
    | `int x -> `int x
    | `uint x -> `uint x
    | `float x -> gen_float x
    | `bool x -> `bool x
    | `string x -> gen_string x
    | `binary x -> gen_binary x
    | `word x -> `word x
    | `text x -> `text x
    | `any x -> gen_any x
    (* custom types *)
    | `record x -> gen_record x
    | `variant x -> gen_variant x
    | `enum x -> gen_enum x
    | `list x -> gen_list x
    | `alias x -> gen_alias x


(* TODO: provide more precise locations for fields, options, etc *)
and gen_obj x = Piq_parser.piq_reference gen_obj0 x


and gen_typed_obj x =
  let name = Piqobj_common.full_typename x in
  let any = T.Any#{ast = Some (gen_obj x); binobj = None } in
  `typed T.Typed#{typename = name; value = any }


and gen_record x =
  open R in
  let fields = x.field in
  `list (List.map gen_field fields)


and gen_field x =
  open F in
  let name = name_of_field x.piqtype in
  let res =
    match x.obj with
      | None -> make_name name
      | Some obj -> make_named name (gen_obj obj)
  in Piq_parser.piq_addrefret x res


and gen_variant x =
  open V in
  gen_option x.option


and gen_option x =
  open O in
  let name = name_of_option x.piqtype in
  let res =
    match x.obj with
      | None -> make_name name
      | Some obj -> make_named name (gen_obj obj)
  in Piq_parser.piq_addrefret x res


and gen_enum x = gen_variant x


and gen_list x = 
  open L in
  `list (List.map gen_obj x.obj)


and gen_alias x =
  open A in
  match x.obj with
    | `alias x -> gen_alias x
    | x -> gen_obj x
