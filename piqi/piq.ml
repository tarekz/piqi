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

(* Piq stream *)


module C = Piqi_common  
open C


let init () = 
  (* TODO: remove init() by moving it to the boot stage, see
   * Piqi.load_piqi for details *)
  Piqi.init ()


exception EOF

(* piq stream object *)
type obj =
  | Piqtype of string
  | Typed_piqobj of Piqobj.obj
  | Piqobj of Piqobj.obj


let open_piq fname =
  init ();
  trace "opening .piq file: %s\n" fname;
  let ch = Piqi_main.open_input fname in
  let piq_parser = Piq_parser.init_from_channel fname ch in
  piq_parser


let read_piq_ast piq_parser :T.ast = 
  let res = Piq_parser.read_next piq_parser in
  match res with
    | Some ast -> ast
    | None -> raise EOF


let piqobj_of_ast ?piqtype ast :Piqobj.obj =
  Piqobj_of_piq.parse_typed_obj ast ?piqtype


let default_piqtype = ref None


let process_default_piqtype typename =
  try
    let piqtype = Piqi_db.find_piqtype typename in
    (* NOTE: silently overriding previous value *)
    default_piqtype := Some piqtype
  with Not_found ->
    error typename ("unknown type: " ^ typename)


let load_piq_obj piq_parser :obj =
  let ast = read_piq_ast piq_parser in
  match ast with
    | `typed {T.Typed.typename = "piqtype";
              T.Typed.value = {T.Any.ast = Some (`word typename)}} ->
        (* :piqtype <typename> *)
        process_default_piqtype typename;
        Piqtype typename
    | `typed {T.Typed.typename = "piqtype"} ->
        error ast "invalid piqtype specification"
    | `typename x ->
        error x "invalid piq object"
    | `typed _ ->
        let obj = piqobj_of_ast ast in
        Typed_piqobj obj
    | _ when !default_piqtype <> None ->
        let obj = piqobj_of_ast ast ~piqtype:(some_of !default_piqtype) in
        Piqobj obj
    | _ ->
        error ast "type of piq object is unknown"


let make_piqtype typename =
  `typed {
    T.Typed.typename = "piqtype";
    T.Typed.value = {
      T.Any.ast = Some (`word typename);
      T.Any.binobj = None;
    }
  }


let write_piq ch (obj:obj) =
  let ast =
    match obj with
      | Piqtype typename ->
          make_piqtype typename
      | Typed_piqobj obj ->
          Piqobj_to_piq.gen_typed_obj obj
      | Piqobj obj ->
          Piqobj_to_piq.gen_obj obj
  in
  Piq_gen.to_channel ch ast;
  (* XXX: add one extra newline for better readability *)
  Pervasives.output_char ch '\n'


let open_wire fname =
  init ();
  trace "opening .wire file: %s\n" fname;
  let ch = Piqi_main.open_input fname in
  let buf = Piqirun_parser.init_from_channel ch in
  buf


let read_wire_field buf =
  (* TODO: handle runtime wire read errors *)
  if Piqirun_parser.is_empty buf
  then raise EOF
  else Piqirun_parser.parse_field buf


let piqtypes = ref []

let add_piqtype code piqtype =
  if code = 1 (* default piqtype *)
  then
    (* NOTE: silently overriding previous value *)
    default_piqtype := Some piqtype
  else
    let code = (code+1)/2 in
    piqtypes := (code, piqtype) :: !piqtypes


let find_piqtype_by_code code =
  try
    let (_,piqtype) =
      List.find
        (function (code',_) when code = code' -> true | _ -> false)
        !piqtypes
    in piqtype
  with
    Not_found ->
      (* TODO: add stream position info *)
      piqi_error
        ("invalid field code when reading .wire: " ^ string_of_int code)


let process_piqtype code typename =
  let piqtype =
    try Piqi_db.find_piqtype typename
    with Not_found ->
      (* TODO: add stream position info *)
      piqi_error ("unknown type: " ^ typename)
  in
  add_piqtype code piqtype


let rec load_wire_obj buf :obj =
  let field_code, field_obj = read_wire_field buf in
  match field_code with
    | c when c mod 2 = 1 ->
        let typename = Piqirun_parser.parse_string field_obj in
        process_piqtype c typename;
        if c = 1
        then
          (* :piqtype <typename> *)
          Piqtype typename
        else
          (* we've just read type-code binding information;
             proceed to the next stream object *)
          load_wire_obj buf
    | 2 when !default_piqtype <> None ->
        let piqtype = some_of !default_piqtype in
        let obj = Piqobj_of_wire.parse_obj piqtype field_obj in
        Piqobj obj
    | 2 ->
        (* TODO: add stream position info *)
        piqi_error "default type for piq wire object is unknown"
    | c -> (* the code is even which means typed piqobj *)
        let piqtype = find_piqtype_by_code (c/2) in
        let obj = Piqobj_of_wire.parse_obj piqtype field_obj in
        Typed_piqobj obj


let out_piqtypes = ref []
let next_out_code = ref 2


let gen_piqtype code typename =
  Piqirun_gen.gen_string code typename


let write_piqtype ch code typename =
  let data = gen_piqtype code typename in
  Piqirun_gen.to_channel ch data


let find_add_piqtype_code ch name =
  try 
    let (_, code) =
      List.find
        (function (name',_) when name = name' -> true | _ -> false)
        !out_piqtypes
    in code
  with Not_found ->
    let code = !next_out_code * 2 in
    incr next_out_code;
    out_piqtypes := (name, code)::!out_piqtypes;
    write_piqtype ch (code-1) name;
    code

 
let write_wire ch (obj :obj) =
  let data =
    match obj with
      | Piqtype typename ->
          gen_piqtype 1 typename
      | Piqobj obj ->
          Piqobj_to_wire.gen_obj 2 obj
      | Typed_piqobj obj ->
          let typename = Piqobj_common.full_typename obj in
          let code = find_add_piqtype_code ch typename in
          Piqobj_to_wire.gen_obj code obj
  in
  Piqirun_gen.to_channel ch data


let open_pb fname =
  trace "opening .pb file: %s\n" fname;
  let ch = Piqi_main.open_input fname in
  let buf = Piqirun_parser.Block.init_from_channel ch in
  buf


(* NOTE: that function can be called exactly once *)
let load_pb (piqtype:T.piqtype) wireobj :Piqobj.obj =
  (* TODO: handle runtime wire read errors *)
  Piqobj_of_wire.parse_obj piqtype wireobj


let write_pb ch (obj :Piqobj.obj) =
  let piqtype = Piqobj_common.type_of obj in

  (match unalias piqtype with
    | `record _ | `variant _ | `list _ -> ()
    | _ ->
        piqi_error "only records, variants and lists can be written to .pb"
  );

  let buf = Piqobj_to_wire.gen_embedded_obj obj in
  Piqirun_gen.to_channel ch buf
