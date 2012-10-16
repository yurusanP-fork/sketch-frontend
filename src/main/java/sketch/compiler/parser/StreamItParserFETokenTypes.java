// $ANTLR 2.7.7 (2006-11-01): "StreamItParserFE.g" -> "StreamItParserFE.java"$

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
import java.util.Map;
import java.util.HashMap;

import sketch.compiler.Directive;
import sketch.compiler.ast.core.FEContext;
import sketch.compiler.ast.core.FieldDecl;
import sketch.compiler.ast.core.Function;
import sketch.compiler.ast.core.Parameter;
import sketch.compiler.ast.core.Program;
import sketch.compiler.ast.core.Annotation;
import sketch.util.datastructures.HashmapList;

import sketch.compiler.ast.core.Package;


import sketch.compiler.ast.core.exprs.*;
import sketch.compiler.ast.core.exprs.regens.*;
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
	int TK_assume = 14;
	int TK_boolean = 15;
	int TK_float = 16;
	int TK_bit = 17;
	int TK_int = 18;
	int TK_void = 19;
	int TK_double = 20;
	int TK_fun = 21;
	int TK_char = 22;
	int TK_struct = 23;
	int TK_ref = 24;
	int TK_if = 25;
	int TK_else = 26;
	int TK_while = 27;
	int TK_for = 28;
	int TK_switch = 29;
	int TK_case = 30;
	int TK_default = 31;
	int TK_break = 32;
	int TK_do = 33;
	int TK_continue = 34;
	int TK_return = 35;
	int TK_true = 36;
	int TK_false = 37;
	int TK_parfor = 38;
	int TK_until = 39;
	int TK_by = 40;
	int TK_implements = 41;
	int TK_assert = 42;
	int TK_assert_max = 43;
	int TK_h_assert = 44;
	int TK_generator = 45;
	int TK_harness = 46;
	int TK_library = 47;
	int TK_printfcn = 48;
	int TK_device = 49;
	int TK_global = 50;
	int TK_serial = 51;
	int TK_spmdfork = 52;
	int TK_stencil = 53;
	int TK_include = 54;
	int TK_pragma = 55;
	int TK_package = 56;
	int ARROW = 57;
	int LARROW = 58;
	int WS = 59;
	int LINERESET = 60;
	int SL_COMMENT = 61;
	int ML_COMMENT = 62;
	int LPAREN = 63;
	int RPAREN = 64;
	int LCURLY = 65;
	int RCURLY = 66;
	int LSQUARE = 67;
	int RSQUARE = 68;
	int PLUS = 69;
	int PLUS_EQUALS = 70;
	int INCREMENT = 71;
	int MINUS = 72;
	int MINUS_EQUALS = 73;
	int DECREMENT = 74;
	int STAR = 75;
	int STAR_EQUALS = 76;
	int DIV = 77;
	int DIV_EQUALS = 78;
	int MOD = 79;
	int LOGIC_AND = 80;
	int LOGIC_OR = 81;
	int BITWISE_AND = 82;
	int BITWISE_OR = 83;
	int BITWISE_XOR = 84;
	int ASSIGN = 85;
	int DEF_ASSIGN = 86;
	int EQUAL = 87;
	int NOT_EQUAL = 88;
	int LESS_THAN = 89;
	int LESS_EQUAL = 90;
	int MORE_THAN = 91;
	int MORE_EQUAL = 92;
	int QUESTION = 93;
	int COLON = 94;
	int SEMI = 95;
	int COMMA = 96;
	int DOT = 97;
	int BANG = 98;
	int LSHIFT = 99;
	int RSHIFT = 100;
	int NDVAL = 101;
	int NDVAL2 = 102;
	int SELECT = 103;
	int NDANGELIC = 104;
	int AT = 105;
	int BACKSLASH = 106;
	int LESS_COLON = 107;
	int REGEN = 108;
	int CHAR_LITERAL = 109;
	int STRING_LITERAL = 110;
	int ESC = 111;
	int DIGIT = 112;
	int HQUAN = 113;
	int NUMBER = 114;
	int ID = 115;
}
