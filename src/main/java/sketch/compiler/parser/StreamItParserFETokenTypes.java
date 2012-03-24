// $ANTLR 2.7.7 (20060906): "StreamItParserFE.g" -> "StreamItParserFE.java"$

package sketch.compiler.parser;

import java.io.DataInputStream;
import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Set;
import java.util.Vector;

import sketch.compiler.Directive;
import sketch.compiler.ast.core.FEContext;
import sketch.compiler.ast.core.FieldDecl;
import sketch.compiler.ast.core.Function;
import sketch.compiler.ast.core.Parameter;
import sketch.compiler.ast.core.Program;

import sketch.compiler.ast.core.StreamSpec;


import sketch.compiler.ast.core.exprs.*;
import sketch.compiler.ast.core.stmts.*;
import sketch.compiler.ast.core.typs.*;
import sketch.compiler.ast.cuda.exprs.*;
import sketch.compiler.ast.cuda.stmts.*;
import sketch.compiler.ast.cuda.typs.*;

import sketch.compiler.ast.promela.stmts.StmtFork;
import sketch.compiler.main.cmdline.SketchOptions;

import sketch.compiler.ast.spmd.stmts.StmtSpmdfork;

import static sketch.util.DebugOut.assertFalse;

public interface StreamItParserFETokenTypes {
	int EOF = 1;
	int NULL_TREE_LOOKAHEAD = 3;
	int TK_atomic = 4;
	int TK_fork = 5;
	int TK_insert = 6;
	int TK_into = 7;
	int TK_loop = 8;
	int TK_repeat = 9;
	int TK_minrepeat = 10;
	int TK_new = 11;
	int TK_null = 12;
	int TK_reorder = 13;
	int TK_boolean = 14;
	int TK_float = 15;
	int TK_bit = 16;
	int TK_int = 17;
	int TK_void = 18;
	int TK_double = 19;
	int TK_complex = 20;
	int TK_fun = 21;
	int TK_struct = 22;
	int TK_ref = 23;
	int TK_if = 24;
	int TK_else = 25;
	int TK_while = 26;
	int TK_for = 27;
	int TK_switch = 28;
	int TK_case = 29;
	int TK_default = 30;
	int TK_break = 31;
	int TK_do = 32;
	int TK_continue = 33;
	int TK_return = 34;
	int TK_true = 35;
	int TK_false = 36;
	int TK_parfor = 37;
	int TK_until = 38;
	int TK_by = 39;
	int TK_implements = 40;
	int TK_assert = 41;
	int TK_h_assert = 42;
	int TK_generator = 43;
	int TK_harness = 44;
	int TK_library = 45;
	int TK_printfcn = 46;
	int TK_device = 47;
	int TK_global = 48;
	int TK_serial = 49;
	int TK_spmdfork = 50;
	int TK_stencil = 51;
	int TK_include = 52;
	int TK_pragma = 53;
	int TK_package = 54;
	int ARROW = 55;
	int LARROW = 56;
	int WS = 57;
	int LINERESET = 58;
	int SL_COMMENT = 59;
	int ML_COMMENT = 60;
	int LPAREN = 61;
	int RPAREN = 62;
	int LCURLY = 63;
	int RCURLY = 64;
	int LSQUARE = 65;
	int RSQUARE = 66;
	int PLUS = 67;
	int PLUS_EQUALS = 68;
	int INCREMENT = 69;
	int MINUS = 70;
	int MINUS_EQUALS = 71;
	int DECREMENT = 72;
	int STAR = 73;
	int STAR_EQUALS = 74;
	int DIV = 75;
	int DIV_EQUALS = 76;
	int MOD = 77;
	int LOGIC_AND = 78;
	int LOGIC_OR = 79;
	int BITWISE_AND = 80;
	int BITWISE_OR = 81;
	int BITWISE_XOR = 82;
	int ASSIGN = 83;
	int DEF_ASSIGN = 84;
	int EQUAL = 85;
	int NOT_EQUAL = 86;
	int LESS_THAN = 87;
	int LESS_EQUAL = 88;
	int MORE_THAN = 89;
	int MORE_EQUAL = 90;
	int QUESTION = 91;
	int COLON = 92;
	int SEMI = 93;
	int COMMA = 94;
	int DOT = 95;
	int BANG = 96;
	int LSHIFT = 97;
	int RSHIFT = 98;
	int NDVAL = 99;
	int NDVAL2 = 100;
	int SELECT = 101;
	int AT = 102;
	int REGEN = 103;
	int CHAR_LITERAL = 104;
	int STRING_LITERAL = 105;
	int ESC = 106;
	int DIGIT = 107;
	int HQUAN = 108;
	int NUMBER = 109;
	int ID = 110;
	int TK_pi = 111;
}
