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


module W = Piqi_wire


module Gen = Piqirun_gen


(* providing special handling for boxed objects, since they are not
 * actual references and can not be uniquely identified. Moreover they can
 * mask integers which are used for enumerating objects *)
let refer obj =
  let count = Piqloc.next_ocount () in
  if not (Obj.is_int (Obj.repr obj))
  then Piqloc.addref obj count
  else ()


let reference f code x =
  refer x;
  f code x


(* XXX: move to Piqi_wire? *)
let gen_int ?wire_type code x =
  let wire_type = W.get_wire_type `int wire_type in
  let gen_f =
    match wire_type with
      | `varint -> Gen.int64_to_varint
      | `zigzag_varint -> Gen.int64_to_zigzag_varint
      | `fixed32 -> Gen.int64_to_fixed32
      | `fixed64 -> Gen.int64_to_fixed64
      | `signed_varint -> Gen.int64_to_signed_varint
      | `signed_fixed32 -> Gen.int64_to_signed_fixed32
      | `signed_fixed64 -> Gen.int64_to_signed_fixed64
      | `block -> assert false (* XXX *)
  in
  gen_f code x


let gen_float ?wire_type code x =
  let wire_type = W.get_wire_type `float wire_type in
  let gen_f =
    match wire_type with
      | `fixed32 -> Gen.float_to_fixed32
      | `fixed64 -> Gen.float_to_fixed64
      | _ -> assert false (* XXX *)
  in
  gen_f code x


let gen_bool = Gen.gen_bool
let gen_string = Gen.gen_string


let gen_int ?wire_type code x =
  refer x;
  gen_int ?wire_type code x

let gen_float ?wire_type code x =
  refer x;
  gen_float ?wire_type code x

let gen_bool = reference gen_bool
let gen_string = reference gen_string


let compare_field_type a b =
  match a.T.Field#code, b.T.Field#code with
    | Some a, Some b -> Int32.to_int (Int32.sub a b)
    (*
    | Some a, Some b -> a - b
    *)
    | _ -> assert false


let compare_field a b =
  open F in
  compare_field_type a.piqtype b.piqtype


(* preorder fields by their codes *)
let order_fields = List.sort compare_field


(*
let rec unalias (x:Piqobj.obj) =
  match x with
    | `alias x -> unalias x.A#obj
    | x -> x
*)


let rec gen_obj code (x:Piqobj.obj) =
  match x with
    (* built-in types *)
    | `int x | `uint x -> gen_int code x
    | `float x -> gen_float code x
    | `bool x -> gen_bool code x
    | `string x -> gen_string code x
    | `binary x -> gen_string code x
    | `word x -> gen_string code x
    | `text x -> gen_string code x
    | `any x -> gen_any code x
    (* custom types *)
    | `record x -> reference gen_record code x
    | `variant x -> reference gen_variant code x
    | `enum x -> reference gen_enum code x
    | `list x -> reference gen_list code x
    | `alias x -> gen_alias code x


(* generate obj without leading code/tag element *)
and gen_embedded_obj obj =
  (* -1 is a special code meaning that key and length for blocks should not be
   * generated *)
  gen_obj (-1) obj


(* XXX: provide separate functions: gen_binobj and gen_typed_binobj *)
and gen_binobj ?(named=true) x = 
  if not named 
  then
    Gen.gen_binobj gen_obj x
  else
    let name = Piqobj_common.full_typename x in
    Gen.gen_binobj gen_obj x ~name


and gen_any code x =
  open Any in
  begin
    (* don't generate if x.any.bin already exists *)
    (if x.any.T.Any.binobj = None &&
        (* normally x.obj is defined, but sometimes, for example, during
         * bootstrap for field's default ANY it is unknown *)
        x.obj <> None
    then
      (* generate "x.any.binobj" from "x.obj" *)
      let binobj = gen_binobj (some_of x.obj) in
      Piqloc.add_fake_loc binobj ~label:"_binobj";
      x.any.T.Any.binobj <- Some binobj);
    (* generate "Piqtype.any" record *)
    Piqloc.check_add_fake_loc x.any ~label:"_any";
    T.gen_any code x.any
  end


and gen_record code x =
  open R in
  (* TODO, XXX: doing ordering at every generation step is inefficient *)
  let fields = order_fields x.field in
  Gen.gen_record code (List.map gen_field fields)


and gen_field x =
  open F in
  let code = Int32.to_int (some_of x.piqtype.T.Field#code) in
  match x.obj with
    | None ->
        (* using true for encoding flags -- the same encoding as for options
         * (see below) *)
        refer x;
        Gen.gen_bool code true
    | Some obj -> gen_obj code obj


and gen_variant code x =
  open V in
  (* generate a record with a single field which represents variant's option *)
  Gen.gen_record code [gen_option x.option]


and gen_option x =
  open O in
  let code = Int32.to_int (some_of x.piqtype.T.Option#code) in
  match x.obj with
    | None ->
        (* using true for encoding options w/o value *)
        refer x;
        Gen.gen_bool code true
    | Some obj ->
        gen_obj code obj


and gen_enum code x =
  open E in
  gen_enum_option code x.option


and gen_enum_option code x =
  open O in
  let value = some_of x.piqtype.T.Option#code in
  (*
  Gen.gen_varint code value
  *)
  Gen.int32_to_varint code value


and gen_list code x = 
  open L in
  Gen.gen_list gen_obj code x.obj


and gen_alias ?wire_type code x =
  open A in
  let this_wire_type = x.piqtype.T.Alias#wire_type in
  (* wire-type defined in this alias trumps wire-type passed by the upper
   * definition *)
  (* XXX: report a wire-type conflict rather than silently use the default? *)
  let wire_type =
    match wire_type, this_wire_type with
      | _, Some _ -> this_wire_type
      | _ -> wire_type
  in
  gen_alias_obj code x.obj ?wire_type 


and gen_alias_obj ?wire_type code (x:Piqobj.obj) =
  match x with
    | `int x | `uint x -> gen_int code x ?wire_type
    | `float x -> gen_float code x ?wire_type
    | `alias x -> gen_alias code x ?wire_type
    | _ -> gen_obj code x
