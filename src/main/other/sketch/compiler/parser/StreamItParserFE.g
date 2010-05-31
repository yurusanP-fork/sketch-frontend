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

import sketch.compiler.Directive;
import sketch.compiler.ast.core.FEContext;
import sketch.compiler.ast.core.FieldDecl;
import sketch.compiler.ast.core.Function;
import sketch.compiler.ast.core.Parameter;
import sketch.compiler.ast.core.Program;
import sketch.compiler.ast.core.SplitterJoiner;
import sketch.compiler.ast.core.StreamSpec;
import sketch.compiler.ast.core.StreamType;
import sketch.compiler.ast.core.exprs.*;
import sketch.compiler.ast.core.stmts.*;
import sketch.compiler.ast.core.typs.Type;
import sketch.compiler.ast.core.typs.TypeArray;
import sketch.compiler.ast.core.typs.TypePortal;
import sketch.compiler.ast.core.typs.TypePrimitive;
import sketch.compiler.ast.core.typs.TypeStruct;
import sketch.compiler.ast.core.typs.TypeStructRef;
import sketch.compiler.ast.promela.stmts.StmtFork;
import sketch.compiler.main.seq.SequentialSketchOptions;
import sketch.compiler.passes.streamit_old.SJDuplicate;
import sketch.compiler.passes.streamit_old.SJRoundRobin;
import sketch.compiler.passes.streamit_old.SJWeightedRR;
}

{@SuppressWarnings("deprecation")}
class StreamItParserFE extends Parser;
options {
	importVocab=StreamItLex;	// use vocab generated by lexer
}

{
	private Set<String> processedIncludes=new HashSet<String> ();
    private Set<Directive> directives = new HashSet<Directive> ();
    private boolean preprocess;
    private List<String> cppDefs;

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

    public void handleInclude(String name, List funcs, List vars, List structs)
    {
        try {
            List<String> incList = Arrays.asList(
                    SequentialSketchOptions.getSingleton().feOpts.inc);
        	Iterator<String> lit = null;
        	if(incList != null){ lit = incList.iterator(); }
        	File f = new File (name);
        	String errMsg = "";
        	while(!f.canRead()){
        		if(lit != null && lit.hasNext()){
        			String tmp = lit.next(); 
        			errMsg += "\n\t" +  f.getCanonicalPath();
        			f = new File (tmp, name);	
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
		assert p.getStreams().size() == 1;

		StreamSpec ss = (StreamSpec) p.getStreams().get(0);
		funcs.addAll(ss.getFuncs());
		vars.addAll(ss.getVars());
		structs.addAll(p.getStructs());
        directives.addAll (parser.getDirectives ());
    }

    private void handlePragma (String pragma, String args) {
        directives.add (Directive.make (pragma, args));
    }

    public Set<Directive> getDirectives () {  return directives;  }

}// end of ANTLR header block

program	 returns [Program p]
{ p = null; List vars = new ArrayList();  List streams = new ArrayList();
	List funcs=new ArrayList(); Function f;
    FieldDecl fd; TypeStruct ts; List<TypeStruct> structs = new ArrayList<TypeStruct>();
    String file = null;
}
	:	(  ((TK_harness | TK_generator)? return_type ID LPAREN) => f=function_decl { funcs.add(f); }
           |    (return_type ID LPAREN) => f=function_decl { funcs.add(f); }
           |    fd=field_decl SEMI { vars.add(fd); }
           |    ts=struct_decl { structs.add(ts); }
           |    file=include_stmt { handleInclude (file, funcs, vars, structs); }
           |    pragma_stmt
        )*
		EOF
		// Can get away with no context here.
		{
			 StreamSpec ss=new StreamSpec((FEContext) null, StreamSpec.STREAM_FILTER,
 				new StreamType((FEContext) null, TypePrimitive.bittype, TypePrimitive.bittype), "MAIN",
 				Collections.EMPTY_LIST, vars, funcs);
 				streams.add(ss);
				 if (!hasError) p = new Program(null, Collections.singletonList(ss), structs); }
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


stream_type_decl returns [StreamType st] { st = null; Type in, out; }
	:	in=data_type t:ARROW out=data_type
		// Again, want context from the input type, but Types aren't
		// FENodes.
		{ st = new StreamType(getContext(t), in, out); }
	;

struct_stream_decl[StreamType st] returns [StreamSpec ss]
{ ss = null; int type = 0;
	List params = Collections.EMPTY_LIST; Statement body; }
	:	( TK_pipeline { type = StreamSpec.STREAM_PIPELINE; }
		| TK_splitjoin { type = StreamSpec.STREAM_SPLITJOIN; }
		| TK_feedbackloop { type = StreamSpec.STREAM_FEEDBACKLOOP; }
		| TK_sbox { type = StreamSpec.STREAM_TABLE; }
		)
		id:ID
		(params=param_decl_list)?
		body=block
		{ ss = new StreamSpec(st.getContext(), type, st, id.getText(),
				params, body); }
	;



statement returns [Statement s] { s = null; }
	:	s=loop_statement
	|   s=minrepeat_statement
	|   s=fork_statement	
	|	s=insert_block
	|	s=reorder_block
	|	s=atomic_block
	|	s=block
	|	(data_type ID) => s=variable_decl SEMI!
	|	(expr_statement) => s=expr_statement SEMI!
	|	tb:TK_break SEMI { s = new StmtBreak(getContext(tb)); }
	|	tc:TK_continue SEMI { s = new StmtContinue(getContext(tc)); }
	|	s=if_else_statement
	|	s=while_statement
	|	s=do_while_statement SEMI
	|	s=for_statement
	|	s=assert_statement SEMI
	|s=return_statement SEMI
	|t:SEMI {s=new StmtEmpty(getContext(t));}
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




splitter_or_joiner returns [SplitterJoiner sj]
{ sj = null; Expression x; List l; }
	: tr:TK_roundrobin
		( (LPAREN RPAREN) => LPAREN RPAREN
			{ sj = new SJRoundRobin(getContext(tr)); }
		| (LPAREN right_expr RPAREN) => LPAREN x=right_expr RPAREN
			{ sj = new SJRoundRobin(getContext(tr), x); }
		| l=func_call_params { sj = new SJWeightedRR(getContext(tr), l); }
		| { sj = new SJRoundRobin(getContext(tr)); }
		)
	| td:TK_duplicate (LPAREN RPAREN)?
		{ sj = new SJDuplicate(getContext(td)); }
	| tag: ID (LPAREN RPAREN)?
		{
			if( tag.getText().equals("xor") ){
				sj = new SJDuplicate(getContext(tag), SJDuplicate.XOR );
			}else if( tag.getText().equals("or") ){
				sj = new SJDuplicate(getContext(tag), SJDuplicate.OR );
			}else if( tag.getText().equals("and") ){
				sj = new SJDuplicate(getContext(tag), SJDuplicate.AND );
			}else{
				assert false: tag.getText()+ " is not a valid splitter";
			}
		}
	;


data_type returns [Type t] { t = null; Expression x; }
	:	(t=primitive_type | id:ID { t = new TypeStructRef(id.getText()); })
		(	l:LSQUARE
			(x=right_expr { t = new TypeArray(t, x); }
			| { throw new SemanticException("missing array bounds in type declaration", getFilename(), l.getLine()); }
			)
			RSQUARE
		)*
	|	TK_void { t =  TypePrimitive.voidtype; }
	|	TK_portal LESS_THAN pn:ID MORE_THAN
		{ t = new TypePortal(pn.getText()); }
	;

primitive_type returns [Type t] { t = null; }
	:	TK_boolean { t = TypePrimitive.booltype; }
	|	TK_bit { t = TypePrimitive.bittype;  }
	|	TK_int { t = TypePrimitive.inttype;  }
	|	TK_float { t = TypePrimitive.floattype;  }
	|	TK_double { t = TypePrimitive.doubletype; }
	|	TK_complex { t = TypePrimitive.cplxtype; }
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

function_decl returns [Function f] { Type rt; List l; StmtBlock s; f = null; boolean isHarness=false; boolean isGenerator=false; }
	:
	(TK_harness { isHarness=true; })?
	(TK_generator { isGenerator=true;} )?
	rt=return_type
	id:ID
	l=param_decl_list
	(TK_implements impl:ID)?
	( s=block
	{
			assert !(isGenerator && isHarness) : "The generator and harness keywords cannot be used together";
			if (isGenerator) {
                f = Function.newHelper(getContext(id), id.getText(), rt, l,
                    impl==null ? null : impl.getText(), s);
			} else if (isHarness) {
                assert impl == null;
				f = Function.newHarnessMain(getContext(id), id.getText(), rt, l, s);
			} else {
                f = Function.newStatic(getContext(id), id.getText(), rt, l,
                    impl==null ? null : impl.getText(), s);
			}
	}
	| SEMI  { f = Function.newUninterp(getContext(id),id.getText(), rt, l);   })
	;

return_type returns [Type t] { t=null; }
	: 	t=data_type
	;

handler_decl returns [Function f] { List l; Statement s; f = null;
Type t = TypePrimitive.voidtype;
int cls = Function.FUNC_HANDLER; }
	:	TK_handler id:ID l=param_decl_list s=block
		{ f = new Function(getContext(id), cls, id.getText(), t, l, s); }
	;

param_decl_list returns [List l] { l = new ArrayList(); Parameter p; }
	:	LPAREN
		(p=param_decl { l.add(p); } (COMMA p=param_decl { l.add(p); })*
		)?
		RPAREN
	;

param_decl returns [Parameter p] { Type t; p = null; boolean isRef=false; }
	: 	(TK_ref { isRef=true;} )?	 t=data_type id:ID { p = new Parameter(t, id.getText(), isRef? Parameter.REF : Parameter.IN); }
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

assert_statement returns [StmtAssert s] { s = null; Expression x; }
	:	(t1:TK_assert | t2:TK_h_assert) x=right_expr (COLON ass:STRING_LITERAL)?{
		String msg = null;
		Token t = t1;
		if(t==null){ t=t2;}
		FEContext cx =getContext(t); 
		if(ass!=null){
			String ps = ass.getText();
	        ps = ps.substring(1, ps.length()-1);
			msg =cx + "   "+ ps;	
		}
		s = new StmtAssert(cx, x, msg, t2!=null); }	
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
		(x=right_expr | { x = new ExprConstBoolean(getContext(t), true); })
		SEMI b=for_incr_statement RPAREN c=pseudo_block
		{ s = new StmtFor(getContext(t), a, x, b, c); }
	;

for_init_statement returns [Statement s] { s = null; }
	:	(variable_decl) => s=variable_decl
	|	(expr_statement) => s=expr_statement
	|   (t:SEMI) /* empty */ => { s = new StmtEmpty(getContext(t)); }
	;

for_incr_statement returns [Statement s] { s = null; }
	:	s=expr_statement
	|   /* empty */ { s = new StmtEmpty((FEContext) null); }
	;

expr_statement returns [Statement s] { s = null; Expression x; }
	:	(incOrDec) => x=incOrDec { s = new StmtExpr(x); }
	|	(left_expr (ASSIGN | PLUS_EQUALS | MINUS_EQUALS | STAR_EQUALS | DIV_EQUALS)) => s=assign_expr
	|	(ID LPAREN) => x=func_call { s = new StmtExpr(x); }
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
	:	name:ID l=func_call_params
		{ x = new ExprFunCall(getContext(name), name.getText(), l); }
	;

func_call_params returns [List l] { l = new ArrayList(); Expression x; }
	:	LPAREN
		(	x=right_expr { l.add(x); }
			(COMMA x=right_expr { l.add(x); })*
		)?
		RPAREN
	;

left_expr returns [Expression x] { x = null; }
	:	x=minic_value_exprnofo
	;
	/*|   r:REGEN
        { x = new ExprRegen (getContext (r), r.getText ()); } 
        */

right_expr returns [Expression x] { x = null; }
	:	x=ternaryExpr	
	;

var_initializer returns [Expression x] { x = null; }
: (arr_initializer) => x=arr_initializer
| 	x=right_expr
	;

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



minic_value_expr returns [Expression x] { x = null; List rlist; }
	:	x=tminic_value_expr
		(	DOT field:ID 			{ x = new ExprField(x, x, field.getText()); }
		|	l:LSQUARE
					rlist=array_range_list { x = new ExprArrayRange(x, rlist); }
			RSQUARE
		)*
	;


minic_value_exprnofo returns [Expression x] { x = null; List rlist; }
	:	x=uminic_value_expr
		(	DOT field:ID 			{ x = new ExprField(x, x, field.getText()); }
		|	l:LSQUARE
					rlist=array_range_list { x = new ExprArrayRange(x, rlist); }
			RSQUARE
		)*
	;


uminic_value_expr returns [Expression x] { x = null; }
	:	LPAREN x=right_expr RPAREN
	|	(func_call) => x=func_call
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


constructor_expr returns [Expression x] { x = null; Type t; List l;}
	: n:TK_new t=data_type l=func_call_params {  x = new ExprNew( getContext(n), t);     }
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
array_range_list returns [List l] { l=new ArrayList(); Object r;}
:r=array_range {l.add(r);}
;

array_range returns [Object x] { x=null; Expression start,end,l; }
:start=right_expr {x=new ExprArrayRange.RangeLen(start);}
(COLON
(end=right_expr {x=new ExprArrayRange.Range(start,end);}
|COLON
((NUMBER) => len:NUMBER {x=new ExprArrayRange.RangeLen(start,Integer.parseInt(len.getText()));}
|l=right_expr {x=new ExprArrayRange.RangeLen(start,l);})
))?
;

constantExpr returns [Expression x] { x = null; }
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
			{ x = new ExprConstChar(getContext(c), c.getText()); }
	|	s:STRING_LITERAL
			{ x = new ExprConstStr(getContext(s), s.getText()); }
	|	pi:TK_pi
			{ x = new ExprConstFloat(getContext(pi), Math.PI); }
	|	t:TK_true
			{ x = new ExprConstBoolean(getContext(t), true); }
	|	f:TK_false
			{ x = new ExprConstBoolean(getContext(f), false); }
	|   TK_null
			{ x = ExprNullPtr.nullPtr; }
    |   t1:NDVAL
            { x = new ExprStar(getContext(t1)); }
    |   t2:NDVAL2 (LPAREN n1:NUMBER RPAREN)?
            {  if(n1 != null){
            	  x = new ExprStar(getContext(t2),Integer.parseInt(n1.getText())); 
            	}else{
            	  x = new ExprStar(getContext(t2)); 
            	}
            }    
	;

struct_decl returns [TypeStruct ts]
{ ts = null; Parameter p; List names = new ArrayList();
	List types = new ArrayList(); }
	:	t:TK_struct id:ID
		LCURLY
		(p=param_decl SEMI
			{ names.add(p.getName()); types.add(p.getType()); }
		)*
		RCURLY
		{ ts = new TypeStruct(getContext(t), id.getText(), names, types); }
	;
