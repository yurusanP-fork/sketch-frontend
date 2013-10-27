/*
 * Copyright 2003 by the Massachusetts Institute of Technology.
 *
 * Permission to use, copy, modify, and distribute this
 * software and its documentation for any purpose and without
 * fee is hereby granted, provided that the above copyright
 * notice appear in all copies and that both that copyright
 * notice and this permission notice appear in supporting
 * documentation, and that the name of M.I.T. not be used in
 * advertising or publicity pertaining to distribution of the
 * software without specific, written prior permission.
 * M.I.T. makes no representations about the suitability of
 * this software for any purpose.  It is provided "as is"
 * without express or implied warranty.
 */

/*
 * StreamItParserFE.g: Sketch parser producing front-end tree
 * $Id: StreamItParserFE.g,v 1.41 2008/03/22 02:17:05 cgjones Exp $
 */

header {
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
import sketch.compiler.ast.core.NameResolver;
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
}

{@SuppressWarnings("deprecation")}
class StreamItParserFE extends Parser;
options {
    // NOTE -- increase lookahead depth to support previously
    // ambiguous expressions like expr_named_param
    k = 2;
	importVocab=StreamItLex;	// use vocab generated by lexer
}

{
	private Set<String> processedIncludes=new HashSet<String> ();
    private Set<Directive> directives = new HashSet<Directive> ();
    private boolean preprocess;
    private List<String> cppDefs;
     //ADT
    private List<String> parentStructNames = new ArrayList<String>();

	public StreamItParserFE(StreamItLex lexer, Set<String> includes,
                            boolean preprocess, List<String> cppDefs)
	{
		this(lexer);
		processedIncludes = includes;
        this.preprocess = preprocess;
        this.cppDefs = cppDefs;
	}

	public static void main(String[] args)
	{
		try
		{
			DataInputStream dis = new DataInputStream(System.in);
			StreamItLex lexer = new StreamItLex(dis);
			StreamItParserFE parser = new StreamItParserFE(lexer);
			parser.program();
		}
		catch (Exception e)
		{
			e.printStackTrace(System.err);
		}
	}

	public FEContext getContext(Token t)
	{
		int line = t.getLine();
		if (line == 0) line = -1;
		int col = t.getColumn();
		if (col == 0) col = -1;
		return new FEContext(getFilename(), line, col);
	}

	private boolean hasError = false;

	public void reportError(RecognitionException ex)
	{
		hasError = true;
		super.reportError(ex);
	}

	public void reportError(String s)
	{
		hasError = true;
		super.reportError(s);
	}

    public void handleInclude(String name, List<Package> namespace)
    {
        try {
            List<String> incList = Arrays.asList(
                    SketchOptions.getSingleton().feOpts.inc);
        	Iterator<String> lit = null;
        	if(incList != null){ lit = incList.iterator(); }
        	File f = new File (name);
        	String errMsg = "";
        	while(!f.canRead()){
        		if(lit != null && lit.hasNext()){
        			errMsg += "\n\t" +  f.getCanonicalPath();
        			String tmp = lit.next(); 
        			File tmpf = new File(tmp);
        			String dir = tmpf.getCanonicalPath();
        			f = new File (dir, name);	
        		}else{
        			errMsg += "\n\t" + f.getCanonicalPath();
        			throw new IllegalArgumentException ("File not found: "+ name + "\n" + 
        					"Searched the following paths:" + errMsg + "\n");
        		}
        	}
            name = f.getCanonicalPath ();
        } catch (IOException ioe) {
            throw new IllegalArgumentException ("File not found: "+ name);
        }
        if (processedIncludes.contains(name))
            return;
        processedIncludes.add(name);
        StreamItParser parser =
            new StreamItParser (name, processedIncludes, preprocess, cppDefs);
        Program p = parser.parse ();
		assert p != null;		
		
		namespace.addAll(p.getPackages());		
        directives.addAll (parser.getDirectives ());
    }

    private void handlePragma (String pragma, String args) {
        directives.add (Directive.make (pragma, args));
    }

    public Set<Directive> getDirectives () {  return directives;  }

}// end of ANTLR header block

program	 returns [Program p]
{ p = null; List vars = new ArrayList();  
	List<Function> funcs=new ArrayList(); Function f;
	List<Package> namespaces = new ArrayList<Package>();
    FieldDecl fd; StructDef ts; List<StructDef> structs = new ArrayList<StructDef>();
   
    String file = null;
    String pkgName = null;
    FEContext pkgCtxt = null;
}
	:	(  (annotation_list (/*TK_device  | TK_global |*/  TK_serial | TK_harness |
                     TK_generator | /* TK_library | TK_printfcn |*/ TK_stencil | TK_model)*
                    return_type ID LPAREN) => f=function_decl { funcs.add(f); }
           |    (return_type ID LPAREN) => f=function_decl { funcs.add(f); } 
		   | 	fd=field_decl SEMI { vars.add(fd); }
           |    ts=struct_decl { structs.add(ts); }
           |    file=include_stmt { handleInclude (file, namespaces); }
           |    TK_package id:ID SEMI
				{ pkgCtxt = getContext(id); pkgName = (id.getText()); }
           |    pragma_stmt
        )*
		EOF
		{
			if(pkgName == null){
				pkgName="ANONYMOUS";
			}
			for(StructDef struct : structs){
				if(parentStructNames.contains(struct.getName())) struct.setIsInstantiable(false);
				struct.setPkg(pkgName);	
			}
			for(Function fun : funcs){
				fun.setPkg(pkgName);	
			}
			
			 Package ss=new Package(pkgCtxt, 
 				pkgName,
 				structs, vars, funcs);
 				namespaces.add(ss);
                if (!hasError) {
                    if (p == null) {
                        p = Program.emptyProgram();
                    }
                    p =
                    p.creator().streams(namespaces).create();
                }
                }
	;

include_stmt    returns [String f]  { f = null; }
    :   TK_include fn:STRING_LITERAL SEMI
        {   f = fn.getText ();  f = f.substring (1, f.length () - 1);  }
    ;

pragma_stmt { String args = ""; }
    : TK_pragma p:ID
        ( a:STRING_LITERAL   { args = a.getText ().substring (1, a.getText ().length ()-1); } )?
        SEMI
        { handlePragma (p.getText (), args); }
    ;


field_decl returns [FieldDecl f] { f = null; Type t; Expression x = null;
	List ts = new ArrayList(); List ns = new ArrayList();
	List xs = new ArrayList(); FEContext ctx = null; }
	:	t=data_type id:ID (ASSIGN x=var_initializer)?
		{ ctx = getContext(id); ts.add(t); ns.add(id.getText()); xs.add(x); }
		(
			{ x = null; }
			COMMA id2:ID (ASSIGN x=var_initializer)?
			{ ts.add(t); ns.add(id2.getText()); xs.add(x); }
		)*
		{ f = new FieldDecl(ctx, ts, ns, xs); }
	;





statement returns [Statement s] { s = null; }
	:	s=loop_statement
	|   s=minrepeat_statement
	|   s=fork_statement
        |   s=spmdfork_statement
    |   s=parfor_statement
	|	s=insert_block
	|	s=reorder_block
	|	s=atomic_block
	|	s=block
	|(return_type ID LPAREN) =>s=fdecl_statement
	|	(data_type ID) => s=variable_decl SEMI!
    // |   (ID DEF_ASSIGN) => s=implicit_type_variable_decl SEMI!
	|	(expr_statement) => s=expr_statement SEMI!
	|	tb:TK_break SEMI { s = new StmtBreak(getContext(tb)); }
	|	tc:TK_continue SEMI { s = new StmtContinue(getContext(tc)); }
	//ADT
	|	s=switch_statement
	|	s=if_else_statement
	|	s=while_statement
	|	s=do_while_statement SEMI
	|	s=for_statement
	|	s=assume_statement SEMI
	|	s=assert_statement SEMI
	|	s=assert_max_statement SEMI
	|(annotation_list (TK_device | TK_serial | TK_harness |
                     TK_generator | TK_library | TK_printfcn | TK_stencil | TK_model)*
                    return_type ID LPAREN) =>s=fdecl_statement  
	|s=return_statement SEMI
	|t:SEMI {s=new StmtEmpty(getContext(t));}
	;

fdecl_statement returns [Statement s] { s=null; Function f = null;}
	: f = function_decl { s = new StmtFunDecl(f.getCx(), f); }
	;
	
loop_statement returns [Statement s] { s = null; Expression exp; Statement b; Token x=null;}
	: (t1:TK_loop{x=t1;} | t2:TK_repeat{x=t2;}) LPAREN exp=right_expr RPAREN b=pseudo_block
	{ s = new StmtLoop(getContext(x), exp, b); }
	;

minrepeat_statement returns [Statement s] { s = null; Statement b; Token x=null;}
    : (t1:TK_minrepeat{x=t1;}) b=pseudo_block
    { s = new StmtMinLoop(getContext(x), b); }
    ;

fork_statement returns [Statement s] { s = null; Statement ivar; Expression exp; Statement b;}
	: t:TK_fork LPAREN ivar=variable_decl SEMI exp=right_expr RPAREN b=pseudo_block
	{ s = new StmtFork(getContext(t), (StmtVarDecl) ivar, exp, b); }
	;

spmdfork_statement returns [Statement s] { s = null; String ivar=null; Expression exp; Statement b;}
	: t:TK_spmdfork LPAREN (v:ID {ivar=v.getText();} SEMI)? exp=right_expr RPAREN b=pseudo_block
	{ s = new StmtSpmdfork(getContext(t), ivar, exp, b); }
	;

parfor_statement returns [Statement s] { s = null; Expression ivar; Expression exp; Statement b; }
    : t:TK_parfor LPAREN ivar=var_expr LARROW exp=range_exp RPAREN b=pseudo_block
    { s = new StmtParfor(getContext(t), ivar, exp, b); }
    ;

range_exp returns [Expression e] { e = null; Expression from; Expression until; Expression by = new ExprConstInt(1); }
    : from=right_expr t:TK_until until=right_expr (TK_by by=right_expr)? { }
    { e = new ExprRange(getContext(t), from, until, by); }
    ;




data_type returns [Type t] { t = null; Vector<Expression> params = new Vector<Expression>(); Vector<Integer> maxlens = new Vector<Integer>(); int maxlen = 0; Expression x; boolean isglobal = false; }
	:	 (TK_global {isglobal = true; })? 
                (t=primitive_type 
                | (prefix:ID AT)? id:ID { t = new TypeStructRef(prefix != null ? (prefix.getText() + "@" + id.getText() )  : id.getText(), false); }
                | BITWISE_OR (prefix2:ID AT)? id2:ID BITWISE_OR { t = new TypeStructRef(prefix2 != null ? (prefix2.getText() + "@" + id2.getText() )  : id2.getText(), true); })
		(	l:LSQUARE
			(	
                ( { maxlen = 0; }
                (x=expr_named_param
                	(
					LESS_COLON n:NUMBER { maxlen = Integer.parseInt(n.getText()); }
					)?
				{ params.add(x); maxlens.add(maxlen); }
				)
                | { throw new SemanticException("missing array bounds in type declaration", getFilename(), l.getLine()); })

                ( { maxlen = 0; }
                COMMA x=expr_named_param  
                    (
                    LESS_COLON num:NUMBER { maxlen = Integer.parseInt(num.getText()); }
					)?
				{ params.add(x); maxlens.add(maxlen); }
				)*
			)
            RSQUARE
            {
                while (!params.isEmpty()) {
                    t = new TypeArray(t, params.lastElement(), maxlens.lastElement());
                    params.remove(params.size() - 1);
                    maxlens.remove(maxlens.size() - 1);
                }
            }
		)*
		{
                    if (isglobal) { t = t.withMemType(CudaMemoryType.GLOBAL); } 
                }
	|	TK_void { t =  TypePrimitive.voidtype; }
	;

primitive_type returns [Type t] { t = null; }
	:
		(TK_boolean { t = TypePrimitive.bittype; }
	|	TK_bit { t = TypePrimitive.bittype;  }
	|	TK_int { t = TypePrimitive.inttype;  }
	|	TK_float { t = TypePrimitive.floattype;  }
	|	TK_double { t = TypePrimitive.doubletype; }
	|   TK_fun { t = TypeFunction.singleton; }
	|	TK_char { t = TypePrimitive.chartype; })
	;

variable_decl returns [Statement s] { s = null; Type t; Expression x = null;
	List ts = new ArrayList(); List ns = new ArrayList();
	List xs = new ArrayList(); }
	:	t=data_type
		id:ID
		(ASSIGN x=var_initializer)?
		{ ts.add(t); ns.add(id.getText()); xs.add(x); }
		(
			{ x = null; }
			COMMA id2:ID (ASSIGN x=var_initializer)?
			{ ts.add(t); ns.add(id2.getText()); xs.add(x); }
		)*
		{ s = new StmtVarDecl(getContext (id), ts, ns, xs); }
	;

// implicit_type_variable_decl returns [Statement s] { s = null; Expression init = null; }
//     : id:ID DEF_ASSIGN init=type_or_var_initializer
//     { s = new StmtImplicitVarDecl(getContext(id), id.getText(), init); }
// ;

annotation returns [Annotation an]{
	an = null;
}: atc:AT id:ID LPAREN (slit:STRING_LITERAL)? RPAREN
{
	an = Annotation.newAnnotation(getContext(atc), id.getText(), slit.getText());
}
;

annotation_list returns [HashmapList<String, Annotation>  amap] {
	 amap=null; Annotation an; }
	:	
		( an=annotation {if(amap==null){amap = new HashmapList<String, Annotation>();} amap.append(an.tag, an); })*
	;

function_decl returns [Function f] {
    Type rt;
    List l;
    StmtBlock s;
    HashmapList<String, Annotation> amap;
    f = null;
    boolean isHarness = false;
    boolean isLibrary = false;
    boolean isPrintfcn = false;
    boolean isGenerator = false;
    boolean isDevice = false;
    boolean isGlobal = false;
    boolean isSerial = false;
    boolean isStencil = false;
    boolean isModel = false;
}
	:
	amap=annotation_list
	( 
          TK_serial { isSerial = true; } |
          TK_harness { isHarness = true; } |
          TK_generator { isGenerator = true; }  |      
          TK_stencil { isStencil = true; } | 
          TK_model { isModel = true; }
          
        )*
	rt=return_type
	id:ID
	l=param_decl_list
	(TK_implements impl:ID)?
	( s=block
	{
            assert !(isGenerator && isHarness) : "The generator and harness keywords cannot be used together";
            Function.FunctionCreator fc = Function.creator(getContext(id), id.getText(), Function.FcnType.Static).returnType(
                rt).params(l).body(s).annotations(amap);

            // function type
            if (isGenerator) {
                fc = fc.type(Function.FcnType.Generator);
            } else if (isHarness) {
                assert impl == null : "harness functions cannot have implements";
                fc = fc.type(Function.FcnType.Harness);
            } else if (isModel) {
                assert impl == null : "A model can not implement another model or a concrete function";
                fc = fc.type(Function.FcnType.Model);
            } else if (impl != null) {
                fc = fc.spec(impl.getText());
            }

            // library type
            if (isLibrary) {
                fc = fc.libraryType(Function.LibraryFcnType.Library);
            }

            // print function
            if (isPrintfcn) {
                fc = fc.printType(Function.PrintFcnType.Printfcn);
            }

            // cuda type annotations
            if ((isDevice && isGlobal) || (isGlobal && isSerial) || (isDevice && isSerial)) {
                assertFalse("Only one of \"global\", \"device\", or \"serial\" qualifiers is allowed.");
            }
            if (isDevice) {
                fc = fc.cudaType(Function.CudaFcnType.DeviceInline);
            } else if (isGlobal) {
                fc = fc.cudaType(Function.CudaFcnType.Global);
            } else if (isSerial) {
                fc = fc.cudaType(Function.CudaFcnType.Serial);
            }

            // stencil type
            if (isStencil) {
                fc = fc.solveType(Function.FcnSolveType.Stencil);
            }

            f = fc.create();
	}
	| SEMI  { f = Function.creator(getContext(id), id.getText(), Function.FcnType.Uninterp).returnType(rt).params(l).annotations(amap).create(); })
	;

return_type returns [Type t] { t=null; }
	: 	t=data_type
	;

param_decl_list returns [List l] { l = new ArrayList(); List l2; Parameter p; }
	:	LPAREN
		(l2=impl_param {l.addAll(l2); })?
		(p=param_decl { l.add(p); } (COMMA p=param_decl { l.add(p); })*
		)?
		RPAREN
	;

impl_param returns [List l]{ Parameter p; l = new ArrayList(); }
	: LSQUARE TK_int id:ID {p= new Parameter(getContext(id), TypePrimitive.inttype, id.getText(), Parameter.IN, true); l.add(p);}
	  (COMMA TK_int id2:ID {p= new Parameter(getContext(id), TypePrimitive.inttype, id2.getText(), Parameter.IN, true); l.add(p);})* 
	  RSQUARE COMMA
	;
param_decl returns [Parameter p] { Type t; p = null; boolean isRef=false; }
	: 	(TK_ref { isRef=true;} )?	 t=data_type id:ID { p = new Parameter(getContext(id), t, id.getText(), isRef? Parameter.REF : Parameter.IN, false); }
	;

block returns [StmtBlock sb] { sb=null; Statement s; List l = new ArrayList(); }
	:	t:LCURLY ( s=statement { l.add(s); } )* RCURLY
		{ sb = new StmtBlock(getContext(t), l); }
	;

insert_block returns [StmtInsertBlock ib]
    { ib=null; Statement s; List<Statement> insert = new ArrayList<Statement> (), into = new ArrayList<Statement> (); }
	:	t:TK_insert LCURLY ( s=statement { insert.add(s); } )* RCURLY
		TK_into   LCURLY ( s=statement { into.add(s); } )* RCURLY
		{ ib = new StmtInsertBlock(getContext(t), insert, into); }
	;


reorder_block returns [StmtReorderBlock sb] { sb=null; Statement s; List l = new ArrayList(); }
	:	TK_reorder t:LCURLY ( s=statement { l.add(s); } )* RCURLY
		{ sb = new StmtReorderBlock(getContext(t), l); }
	;

atomic_block returns [StmtAtomicBlock ab] { ab=null; Expression c = null; StmtBlock b = null; }
	:   t:TK_atomic (LPAREN c=right_expr RPAREN)? b=block
		{ ab = new StmtAtomicBlock (getContext (t), b.getStmts (), c); }
	;

pseudo_block returns [StmtBlock sb] { sb=null; Statement s; List l = new ArrayList(); }
	:	 s=statement { l.add(s); }
		{ sb = new StmtBlock(s.getContext(), l); }
	;

return_statement returns [StmtReturn s] { s = null; Expression x = null; }
	:	t:TK_return (x=right_expr)? { s = new StmtReturn(getContext(t), x); }
	;

assume_statement returns [StmtAssume s] { s = null; Expression cond; }
	:   (t:TK_assume) cond = right_expr (COLON ass:STRING_LITERAL)? {
			if (cond != null) {
				String msg = null;
				FEContext cx =getContext(t);
				if(ass!=null){
					String ps = ass.getText();
			        ps = ps.substring(1, ps.length()-1);
					msg = cx + "   "+ ps;	
				}
				s = new StmtAssume(cx, cond, msg);
			}
		}
	;
	
assert_statement returns [StmtAssert s] { s = null; Expression x; }
	:	(t1:TK_assert | t2:TK_h_assert) x=right_expr (COLON ass:STRING_LITERAL)?{
		String msg = null;
		Token t = t1;
		if(t==null){ t=t2;}
		FEContext cx =getContext(t); 
		if(ass!=null){
			String ps = ass.getText();
	        ps = ps.substring(1, ps.length()-1);
			msg = cx + "   "+ ps;	
		}
		s = new StmtAssert(cx, x, msg, t2!=null); }	
	;
	
assert_max_statement returns [StmtAssert s] { s = null; Expression cond; ExprVar var; }
:	t:TK_assert_max (defer: BACKSLASH)? cond=right_expr (COLON ass:STRING_LITERAL)? { 
	FEContext cx = getContext(t);
	String msg = null;
	if (ass != null) {
		String ps = ass.getText();
		ps = ps.substring(1, ps.length()-1);
		msg = cx + "   "+ ps;
	}
	s = StmtAssert.createAssertMax(cx, cond, msg, (defer!=null)); }	
;
//ADT
switch_statement returns [Statement s]
{ s = null; ExprVar  x;  Statement b =null; }
	:	u:TK_switch LPAREN name:ID RPAREN LCURLY
	 
		{x = new ExprVar(getContext(name), name.getText()); s= new StmtSwitch(getContext(u), x); }
		(TK_case caseName:ID COLON b= pseudo_block
		{((StmtSwitch)s).addCaseBlock(caseName.getText(), b);}
		)*
		RCURLY
		
	;
	 

	
if_else_statement returns [Statement s]
{ s = null; Expression x; Statement t, f = null; }
	:	u:TK_if LPAREN x=right_expr RPAREN t=pseudo_block
		((TK_else) => (TK_else f=pseudo_block))?
		{ s = new StmtIfThen(getContext(u), x, t, f); }
	;

while_statement returns [Statement s] { s = null; Expression x; Statement b; }
	:	t:TK_while LPAREN x=right_expr RPAREN b=pseudo_block
		{ s = new StmtWhile(getContext(t), x, b); }
	;

do_while_statement returns [Statement s]
{ s = null; Expression x; Statement b; }
	:	t:TK_do b=pseudo_block TK_while LPAREN x=right_expr RPAREN
		{ s = new StmtDoWhile(getContext(t), b, x); }
	;

for_statement returns [Statement s]
{ s = null; Expression x=null; Statement a, b, c; }
	:	t:TK_for LPAREN a=for_init_statement SEMI
		(x=right_expr | { x = ExprConstInt.one; })
		SEMI b=for_incr_statement RPAREN c=pseudo_block
		{ s = new StmtFor(getContext(t), a, x, b, c, false); }
	;

for_init_statement returns [Statement s] { s = null; }
	:	(variable_decl) => s=variable_decl
    // |   (implicit_type_variable_decl) => s=implicit_type_variable_decl
	|	(expr_statement) => s=expr_statement
	|   /* empty */ { s = new StmtEmpty((FEContext)null); }
	;

for_incr_statement returns [Statement s] { s = null; }
	:	s=expr_statement
	|   /* empty */ { s = new StmtEmpty((FEContext) null); }
	;

expr_statement returns [Statement s] { s = null; Expression x; }
	:	(incOrDec) => x=incOrDec { s = new StmtExpr(x); }
	|	(left_expr (ASSIGN | PLUS_EQUALS | MINUS_EQUALS | STAR_EQUALS | DIV_EQUALS)) => s=assign_expr
	|	(ID (AT ID)? LPAREN) => x=func_call { s = new StmtExpr(x); }
	;

assign_expr returns [Statement s] { s = null; Expression l, r; int o = 0; }
	:	l=left_expr
		(	ASSIGN { o = 0; }
		|	PLUS_EQUALS { o = ExprBinary.BINOP_ADD; }
		|	MINUS_EQUALS { o = ExprBinary.BINOP_SUB; }
		|	STAR_EQUALS { o = ExprBinary.BINOP_MUL; }
		|	DIV_EQUALS { o = ExprBinary.BINOP_DIV; }
		)
		r=right_expr
		{ s = new StmtAssign(l, r, o); s.resetOrigin(); }
	;

func_call returns [Expression x] { x = null; List l; }
	: prefix:ID (AT name:ID)? l=func_call_params
		{ x = new ExprFunCall(getContext(prefix), prefix.getText()+ (name != null ? ("@" + name.getText()) : ""), l); }
	
	;

func_call_params returns [List l] { l = new ArrayList(); Expression x; }
	:	LPAREN
		(	x=expr_named_param { l.add(x); }
			(COMMA x=expr_named_param { l.add(x); })*
		)?
		RPAREN
	;
	
constr_params returns [List l] { l = new ArrayList(); Expression x; }
	:	LPAREN
		(	x=expr_named_param_only { l.add(x); }
			(COMMA x=expr_named_param { l.add(x); })*
		)?
		RPAREN
	;

expr_named_param returns [ Expression x ] { x = null; Token t = null; }
    :   (id:ID ASSIGN)? { t = id; }
        x=right_expr
        {
            if (t != null) {
                x = new ExprNamedParam(getContext(t), t.getText(), x);
            }
        }
    ;

expr_named_param_only returns [ Expression x ] { x = null; Token t = null; }
    :   id:ID ASSIGN x=right_expr { x = new ExprNamedParam(getContext(id), id.getText(), x); }
    ;

left_expr returns [Expression x] { x = null; Vector<ExprArrayRange.RangeLen> rl; }
	:	x=uminic_value_expr
		(	DOT field:ID 			{ x = new ExprField(x, x, field.getText()); }
		|	l:LSQUARE
					rl=array_range { x = new ExprArrayRange(x, x, rl); }
			RSQUARE
		)*
	;

        
right_expr_not_agmax returns [Expression x] { x = null; }
	:	x=ternaryExpr	
	;
right_expr returns [Expression x] { x = null; }
	:	x=right_expr_not_agmax
	|   x=agmax_expr
	;

agmax_expr returns [Expression x] { x = null; }
 	:	t:NDANGELIC (LPAREN n:NUMBER RPAREN)?
    	{
    		if (n != null) {
    			x = new ExprStar(getContext(t), Integer.parseInt(n.getText()), true);
    		} else {
    			x = new ExprStar(getContext(t), true);
    		}
    	} 
	;
	
/*
TODO we don't add exprMax now
agmax_expr returns [Expression x] { x = null; Expression exprMax = null; }
 	:	t:NDANGELIC (LPAREN n:NUMBER RPAREN)? (AT exprMax=right_expr_not_agmax)?
    	{
    		if (n != null) {
    			x = new ExprStar(getContext(t), Integer.parseInt(n.getText()), true, exprMax);
    		} else {
    			x = new ExprStar(getContext(t), true, exprMax);
    		}
    	} 
	;
*/

var_initializer returns [Expression x] { x = null; }
: (arr_initializer) => x=arr_initializer
| 	x=right_expr
	;

type_or_var_initializer returns [Expression x] { x = null; }
: (arr_initializer) => x=arr_initializer
| 	x=right_expr
	;

// type_or_var_initializer returns [Expression x] { x = null; }
// : (var_initializer) => x=var_initializer
//  | x=TypeExpression;

arr_initializer returns [Expression x] { ArrayList l = new ArrayList();
                                         x = null;
                                         Expression y; }
    : lc:LCURLY
      ( y=var_initializer { l.add(y); }
            (COMMA y=var_initializer { l.add(y); })*
      )?
      RCURLY
        { x = new ExprArrayInit(getContext(lc), l); }
    ;

ternaryExpr returns [Expression x] { x = null; Expression b, c; }
	:	x=logicOrExpr
		(QUESTION b=ternaryExpr COLON c=ternaryExpr
			{ x = new ExprTernary(x, ExprTernary.TEROP_COND,
					x, b, c); }
		)?
	;

logicOrExpr returns [Expression x] { x = null; Expression r; int o = 0; }
	:	x=logicAndExpr
		(LOGIC_OR r=logicAndExpr
			{ x = new ExprBinary(ExprBinary.BINOP_OR, x, r); }
		)*
	;

logicAndExpr returns [Expression x] { x = null; Expression r; }
	:	x=bitwiseOrExpr
		(LOGIC_AND r=bitwiseOrExpr
			{ x = new ExprBinary(ExprBinary.BINOP_AND, x, r); }
		)*
	;

bitwiseOrExpr returns [Expression x] { x = null; Expression r; }
	:	x=bitwiseXorExpr
		(	BITWISE_OR  r=bitwiseXorExpr
			{ x = new ExprBinary(ExprBinary.BINOP_BOR, x, r); }
		)*
	;

bitwiseXorExpr returns [Expression x] { x = null; Expression r; }
    :   x=bitwiseAndExpr
        (   BITWISE_XOR  r=bitwiseAndExpr
            { x = new ExprBinary(ExprBinary.BINOP_BXOR, x, r); }
        )*
    ;

bitwiseAndExpr returns [Expression x] { x = null; Expression r; }
    :   x=equalExpr
        (   BITWISE_AND  r=equalExpr
            { x = new ExprBinary(ExprBinary.BINOP_BAND, x, r); }
        )*
    ;

equalExpr returns [Expression x] { x = null; Expression r; int o = 0; }
	:	x=compareExpr
		(	( EQUAL     { o = ExprBinary.BINOP_EQ; }
			| NOT_EQUAL { o = ExprBinary.BINOP_NEQ; }
			)
			r = compareExpr
			{ x = new ExprBinary(o, x, r); }
		)*
	;

compareExpr returns [Expression x] { x = null; Expression r; int o = 0; }
	:	x=shiftExpr
		(	( LESS_THAN  { o = ExprBinary.BINOP_LT; }
			| LESS_EQUAL { o = ExprBinary.BINOP_LE; }
			| MORE_THAN  { o = ExprBinary.BINOP_GT; }
			| MORE_EQUAL { o = ExprBinary.BINOP_GE; }
			)
			r = shiftExpr
			{ x = new ExprBinary(o, x, r); }
		)*
	;

shiftExpr returns [Expression x] { x=null; Expression r; int op=0; }
    :   x=addExpr
        (   ( LSHIFT {op=ExprBinary.BINOP_LSHIFT;}
            | RSHIFT {op=ExprBinary.BINOP_RSHIFT;}
            )
            r=addExpr
            { x = new ExprBinary(op, x, r); }
        )*
    ;

addExpr returns [Expression x] { x = null; Expression r; int o = 0; }
	:	x=multExpr
		(	( PLUS  { o = ExprBinary.BINOP_ADD; }
			| MINUS { o = ExprBinary.BINOP_SUB; }
			| SELECT { o = ExprBinary.BINOP_SELECT; }
			)
			r=multExpr
			{ x = new ExprBinary(o, x, r); }
		)*
	;

multExpr returns [Expression x] { x = null; Expression r; int o = 0; }
	:	x=inc_dec_expr
		(	( STAR { o = ExprBinary.BINOP_MUL; }
			| DIV  { o = ExprBinary.BINOP_DIV; }
			| MOD  { o = ExprBinary.BINOP_MOD; }
			)
			r=inc_dec_expr
			{ x = new ExprBinary(o, x, r); }
		)*
	;

inc_dec_expr returns [Expression x] { x = null; }
	:	(incOrDec) => x=incOrDec
    |   (LPAREN primitive_type) => x=castExpr
	|	b:BANG x=value_expr { x = new ExprUnary(getContext(b),
												ExprUnary.UNOP_NOT, x); }
	|	x=value_expr
	;

incOrDec returns [Expression x] { x = null; Expression bound = null; Type t = null; }
	:	x=left_expr
		(	INCREMENT
			{ x = new ExprUnary(x.getContext(), ExprUnary.UNOP_POSTINC, x); }
		|	DECREMENT
			{ x = new ExprUnary(x.getContext(), ExprUnary.UNOP_POSTDEC, x); }
		)
	|	i:INCREMENT x=left_expr
			{ x = new ExprUnary(getContext(i), ExprUnary.UNOP_PREINC, x); }
	|	d:DECREMENT x=left_expr
			{ x = new ExprUnary(getContext(d), ExprUnary.UNOP_PREDEC, x); }
            (LPAREN primitive_type) =>
	;

castExpr returns [Expression x] { x = null; Type t = null; Expression bound = null; }
    :   l:LPAREN t=primitive_type
            (sq:LSQUARE  bound=right_expr { t = new TypeArray(t, bound); }  RSQUARE)*
        RPAREN
        x=value_expr
            { x = new ExprTypeCast(getContext(l), t, x); }
    ;

value_expr returns [Expression x] { x = null; boolean neg = false; }
	:
	(	(m:MINUS { neg = true; })?
		(x=minic_value_expr)
		{ if (neg) x = new ExprUnary(getContext(m), ExprUnary.UNOP_NEG, x); }
		)
	;



minic_value_expr returns [Expression x] { x = null; Vector<ExprArrayRange.RangeLen> rl; }
	:	x=tminic_value_expr
		(	DOT field:ID 			{ x = new ExprField(x, x, field.getText()); }
		|	l:LSQUARE
					rl=array_range { x = new ExprArrayRange(x, x, rl); }
			RSQUARE
		)*
	;



uminic_value_expr returns [Expression x] { x = null; }
	:	LPAREN x=right_expr RPAREN
//	|	(func_call) => x=func_call
	| 	(constructor_expr) => x = constructor_expr
	|	x=var_expr	
    |   r:REGEN
            { x = new ExprRegen (getContext (r), r.getText ()); }
	;



tminic_value_expr returns [Expression x] { x = null; }
	:	LPAREN x=right_expr RPAREN
	|	(func_call) => x=func_call
	| 	(constructor_expr) => x = constructor_expr
	|	x=var_expr
	|	x=constantExpr
	|   x=arr_initializer
    |   r:REGEN
            { x = new ExprRegen (getContext (r), r.getText ()); }
	;


constructor_expr returns [Expression x] { x = null; Type t=null; List l;}
	: n:TK_new
	(prefix:ID AT)? id:ID { t = new TypeStructRef(prefix != null ? (prefix.getText() + "@" + id.getText() )  : id.getText(), false); }
	l=constr_params {  x = new ExprNew( getContext(n), t, l);     }
	| BITWISE_OR 
    (prefix2:ID AT)? id2:ID { t = new TypeStructRef(prefix2 != null ? (prefix2.getText() + "@" + id2.getText() )  : id2.getText(), true); }
      BITWISE_OR l=constr_params {  x = new ExprNew( getContext(id2), t, l);     }
	;

var_expr returns [Expression x] { x = null; List rlist; }
:	name:ID { x = new ExprVar(getContext(name), name.getText()); }
	;
	
/*
value returns [Expression x] { x = null; List rlist; }
	:	name:ID { x = new ExprVar(getContext(name), name.getText()); }
		(	DOT field:ID 			{ x = new ExprField(x, x, field.getText()); }
		|	l:LSQUARE
					rlist=array_range_list { x = new ExprArrayRange(x, rlist); }
			RSQUARE
		)*
	;
*/

array_range returns [Vector<ExprArrayRange.RangeLen> x] { x=null; Expression start,end,l; }
    : start=expr_named_param {
        assert (!(start instanceof ExprNamedParam));
        x = new Vector<ExprArrayRange.RangeLen>();
        x.add(new ExprArrayRange.RangeLen(start));
      }
        ( COMMA start=expr_named_param { x.add(new ExprArrayRange.RangeLen(start)); } )*
        (COLON
		  ( end=right_expr {
		  		assert x.size() == 1 : "cannot mix comma indices and array ranges yet";
		  		x.set(0, new ExprArrayRange.RangeLen(start,
		  			new ExprBinary(end, "-", start))); }
		    | COLON
		    l=right_expr {
		    	assert x.size() == 1 : "cannot mix comma indices and array ranges yet";
		    	x.set(0, new ExprArrayRange.RangeLen(start,l)); }
		  )
		)?
    ;

constantExpr returns [Expression x] { x = null; Expression n1=null, n2=null;}
	:	h:HQUAN
			{  String tmp = h.getText().substring(2);
			   Integer iti = new Integer(
	 (int ) ( ( Long.parseLong(tmp, 16) - (long) Integer.MIN_VALUE )
		  % ( (long)Integer.MAX_VALUE - (long) Integer.MIN_VALUE + 1)
		  + Integer.MIN_VALUE) );
				x = ExprConstant.createConstant(getContext(h), iti.toString() ); }
	| 	n:NUMBER
			{ x = ExprConstant.createConstant(getContext(n), n.getText()); }
	|	c:CHAR_LITERAL
			{ x = ExprConstChar.create(c.getText()); }
	|	s:STRING_LITERAL
			{ x = new ExprArrayInit(getContext(s), ExprConstChar.createFromString(s.getText())); }
	|	t:TK_true
			{ x = ExprConstInt.one; }
	|	f:TK_false
			{ x = ExprConstInt.zero; }
	|   TK_null
			{ x = ExprNullPtr.nullPtr; }
    |   t1:NDVAL
            { x = new ExprStar(getContext(t1)); }
    |   t2:NDVAL2 (LPAREN n1=value_expr (COMMA n2=value_expr)? RPAREN)?
            {  if(n1 != null){
            	Integer in1 = n1.getIValue();
            	  if(n2 == null){            	  	
            	  	x = new ExprStar(getContext(t2),in1);
            	  }else{
            	  	Integer in2 = n2.getIValue();
            	  	x = new ExprStar(getContext(t2),in1, in2);
            	  } 
            	}else{
            	  x = new ExprStar(getContext(t2)); 
            	}
            }
    ;
 
struct_decl returns [StructDef ts]
{ ts = null; Parameter p; List names = new ArrayList();
	Annotation an=null;
	HashmapList<String, Annotation> annotations = new HashmapList<String, Annotation>();
	List types = new ArrayList(); }
	:	t:TK_struct id:ID
		//ADT
		(TK_extends parent:ID 
		{
			parentStructNames.add(parent.getText());
		}
		)?
		LCURLY
		(p=param_decl SEMI
			{ names.add(p.getName()); types.add(p.getType()); }
			|
			an=annotation{ annotations.append(an.tag, an); }
		)*
		RCURLY
		{ 
			if(parent != null) {
				ts = StructDef.creator(getContext(t), id.getText(),parent.getText(), true, names, types, annotations).create();
			}else{
				ts = StructDef.creator(getContext(t), id.getText(),null, true, names, types, annotations).create();
			} }
	;
