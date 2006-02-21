package streamit.frontend.passes;

import java.util.*;

import streamit.frontend.nodes.*;
import streamit.frontend.nodes.ExprArrayRange.*;

/**
 * Code generation pass that gets rid of the "bit" data type, using appropriate
 * C types instead. Performs big integer arithmetic on variables that are too
 * large to fit into a single primitive type.
 * 
 * @author liviu
 */
public class BitTypeRemover extends SymbolTableVisitor {

	/**
	 * Symbol table that stores the type of a variable prior to substitution.
	 */
    protected SymbolTable preSymtab;
    /**
     * Unique temporary variable generator
     */
    protected TempVarGen varGen;
    
    public BitTypeRemover(TempVarGen varGen) {
		super(null);
		this.varGen=varGen;
	}

    private static boolean isBitType(Type t)
    {
    	return t instanceof TypePrimitive && ((TypePrimitive)t).getType()==TypePrimitive.TYPE_BIT;
    }

    private static boolean isBitArrayType(Type t)
    {
    	return t instanceof TypeArray && isBitType(((TypeArray)t).getBase());
    }

    private static boolean isArray(Type t)
    {
    	return t instanceof TypeArray;
    }
    
    private static int getWordsize(Type type)
    {
    	if(type instanceof TypePrimitive) {
    		switch(((TypePrimitive)type).getType()) {
    			case TypePrimitive.TYPE_BIT:
    				return 1;
    			case TypePrimitive.TYPE_INT8:
    				return 8;
    			case TypePrimitive.TYPE_INT16:
    				return 16;
    			case TypePrimitive.TYPE_INT32:
    				return 32;
    			case TypePrimitive.TYPE_INT64:
    				return 64;
    		}
    	}
    	return 0;
    }
    
    private static int getArrayWordsize(Type t)
    {
    	if(!(t instanceof TypeArray)) return 0;
    	final Type baseType=((TypeArray)t).getBase();
    	if(baseType instanceof TypePrimitive)
    		return getWordsize(baseType);
    	else
    		return getArrayWordsize(baseType);
    }
    
	private Type convertType(Type type)
	{
		if(type instanceof TypeArray) {
			TypeArray array=(TypeArray)type;
			Type baseType=array.getBase();
			if(baseType instanceof TypeArray) {
				Type newBase=convertType(baseType);
				if(newBase==baseType) return type;
				return new TypeArray(newBase,array.getLength());
			}
			if(isBitType(baseType)) {
				Expression len=array.getLength();
				if(len instanceof ExprConstInt) {
					int val=((ExprConstInt)len).getVal();
					if(val<=8)
						return TypePrimitive.int8type;
					else if(val<=16)
						return TypePrimitive.int16type;
					else if(val<=32)
						return TypePrimitive.int32type;
					else if(val<=64)
						return TypePrimitive.int64type;
					//ok, looks like we'll need an array to store the large integer
					return new TypeArray(TypePrimitive.int32type,
							new ExprConstInt(len.getContext(),(val-1)/32+1));
				}
			}
		}
		else if(isBitType(type)) {
			return TypePrimitive.booltype;
		}
		//fallback case: do nothing
		return type;
	}

    private Type getVarType(Expression e)
    {
    	if(e instanceof ExprVar) {
    		return symtab.lookupVar(((ExprVar)e).getName());
    	}
    	else if(e instanceof ExprArrayRange) {
    		return getVarType(((ExprArrayRange)e).getBase());
    	}
    	return null;
    }
    
    private Type getVarPType(Expression e)
    {
    	if(e instanceof ExprVar) {
    		return preSymtab.lookupVar(((ExprVar)e).getName());
    	}
    	else if(e instanceof ExprArrayRange) {
    		return getVarPType(((ExprArrayRange)e).getBase());
    	}
    	return null;
    }
    
    private static Integer staticEvaluation(Expression e)
    {
    	if(e instanceof ExprConstInt)
    		return ((ExprConstInt)e).getVal();
    	return null;
    }
    
	@Override
	public Object visitFunction(Function func)
	{
		SymbolTable oldPST=preSymtab;
		preSymtab=new SymbolTable(preSymtab);
		boolean change=false;
		List newParams=new ArrayList(func.getParams().size()+1);
        for(Iterator iter = func.getParams().iterator(); iter.hasNext();)
        {
            Parameter param = (Parameter)iter.next();
            Type oldType=param.getType();
            preSymtab.registerVar(param.getName(),oldType);
            Type newType=convertType(oldType);
            if(oldType!=newType) {
            	change=true;
            	newParams.add(new Parameter(newType,param.getName(),param.isParameterOutput()));
            }
            else
            	newParams.add(param);
        }
        if(change)
        	func=new Function(func.getContext(),func.getCls(),func.getName(),func.getReturnType(),newParams,func.getSpecification(),func.getBody());
		Object ret=super.visitFunction(func);
		preSymtab=oldPST;
		return ret;
	}

	@Override
	public Object visitStmtVarDecl(StmtVarDecl stmt)
	{
		boolean change=false; 
		int n=stmt.getNumVars();
		List types=new ArrayList(n+1);
		for(int i=0;i<n;i++) {
			Type oldType=stmt.getType(i);
			preSymtab.registerVar(stmt.getName(i),oldType);
			Type newType=convertType(oldType);
			if(newType!=oldType) change=true;
			types.add(newType);
		}
		if(change)
			stmt=new StmtVarDecl(stmt.getContext(),types,stmt.getNames(),stmt.getInits());
		return super.visitStmtVarDecl(stmt);
	}	

	private Expression convertArrayRange(ExprArrayRange oldExpr, Expression start, int len)
	{
		Expression base=oldExpr.getBase();
		assert base instanceof ExprVar;
		TypeArray pseudotype=(TypeArray) preSymtab.lookupVar((ExprVar)base);
		if(!isBitArrayType(pseudotype)) return oldExpr;

		Type type=symtab.lookupVar((ExprVar)base);
		if(type instanceof TypeArray) {
			throw new UnsupportedOperationException("Cannot deal with big integers at this time.");
		}
		assert type instanceof TypePrimitive;
		if(len>1) {
			throw new UnsupportedOperationException("Cannot deal with array ranges at this time.");
		}
		else {
			Expression sel=new ExprBinary(oldExpr.getContext(),ExprBinary.BINOP_BAND,
					new ExprBinary(oldExpr.getContext(),ExprBinary.BINOP_RSHIFT,
						oldExpr.getBase(),
						start
					),
					new ExprConstInt(oldExpr.getContext(),1)
				);
			return sel;
		}
	}
	
	public Object visitExprArrayRange(ExprArrayRange exp) {
		List ranges=exp.getMembers();
		if(ranges.size()==0) throw new IllegalStateException();
		if(ranges.size()>1) throw new UnsupportedOperationException("Multi-range indexing not currently supported.");
		Object o=ranges.get(0);
		if(o instanceof RangeLen) 
		{
			RangeLen range=(RangeLen) o;
			return convertArrayRange(exp,range.start,range.len);
		}
		else
		{
			Range range=(Range) o;
			if(!(range.start instanceof ExprConstInt) || !(range.end instanceof ExprConstInt))
				throw new UnsupportedOperationException("Cannot deal with array range indexing if the indexes are not statically computable.");
			int start=((ExprConstInt)range.start).getVal();
			int end=((ExprConstInt)range.end).getVal();
			int len=end-start+1;
			assert len>0;
			return convertArrayRange(exp,range.start,len);
		}
		//throw new UnsupportedOperationException("Cannot translate complicated array indexing.");
	}

	private Statement translateSingleWordAssignment(StmtAssign stmt, ExprArrayRange lhs, Type lhsType, int ws, Expression index, int len)
	{
		return translateSingleWordAssignment(stmt, lhs, lhsType, ws, index, len, null);
	}
	
	private Statement translateSingleWordAssignment(StmtAssign stmt, ExprArrayRange lhs, Type lhsType, int ws, Expression index, int len, Expression end)
	{
		final boolean isArray=lhsType instanceof TypeArray; //true if we're dealing with an array of integers (big integer); false if a single integer
		
		//first compute the "new" lhs expression (the word that will be modified)
		final Expression newLhs;
		if(isArray) {
			Expression wsExp=new ExprConstInt(index.getContext(),ws);
			newLhs=new ExprArrayRange(lhs.getBase(),Collections.singletonList(new RangeLen(
				new ExprBinary(index.getContext(),ExprBinary.BINOP_DIV,index,wsExp)
			)));
		}
		else {
			//lhs is an array that fits into a single word
			newLhs=lhs.getBase();
		}
		//then the new rhs
		final Expression newRhs=(Expression) stmt.getRHS().accept(this);
		
		if(len==1)
		{
			final Expression bitSelector;
			if(isArray) {
				Expression wsExp=new ExprConstInt(index.getContext(),ws);
				bitSelector=new ExprBinary(index.getContext(),ExprBinary.BINOP_MOD,index,wsExp);
			}
			else {
				bitSelector=index;
			}
			return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_BITASSIGN",Arrays.asList(new Expression[] {
				newLhs,bitSelector,newRhs
			})));
		}
		
		if(isArray) {
			Expression wsExp=new ExprConstInt(index.getContext(),ws);
			index=new ExprBinary(index.getContext(),ExprBinary.BINOP_MOD,index,wsExp);
		}
		
		final Expression bitMask;
		if(len<=0) {
			bitMask=new ExprFunCall(stmt.getContext(),"SK_ONES_SE",Arrays.asList(new Expression[] {
					index,end
				}));
		}
		else {
			bitMask=new ExprFunCall(stmt.getContext(),"SK_ONES_SL",Arrays.asList(new Expression[] {
				index,new ExprConstInt(index.getContext(),len)
			}));
		}
		final String tempName=varGen.nextVar();
		addStatement(new StmtVarDecl(stmt.getContext(),lhsType,tempName,bitMask));
		
		return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_COPYBITS",Arrays.asList(new Expression[] {
			newLhs,new ExprVar(index.getContext(),tempName),
			new ExprBinary(index.getContext(),ExprBinary.BINOP_LSHIFT,newRhs,index)
		})));
	}
	
	@Override
	public Object visitStmtAssign(StmtAssign stmt)
	{
		final Expression lhs=stmt.getLHS(); //either a variable or an [indexed] array
		{
			final Type lhsPType=getVarPType(lhs);
			assert lhsPType!=null;
			if(!isBitArrayType(lhsPType)) return super.visitStmtAssign(stmt);
		}
			
		final Type lhsType=getVarType(lhs);
		assert lhsType!=null;
		int ws=(lhsType instanceof TypeArray)?getArrayWordsize(lhsType):getWordsize(lhsType);
		assert ws>1;
		
		//assume RHS contains no arithmetic/bitwise operations when LHS is an array range
		if(lhs instanceof ExprArrayRange) {
			final ExprArrayRange expArray=(ExprArrayRange) lhs;
			if(expArray.hasSingleIndex()) {
				// special case: a[i]=x --> always affects a single word; no loops
				Expression index=expArray.getSingleIndex();
				return translateSingleWordAssignment(stmt,expArray,lhsType,ws,index,1);
			}
			else {
				// general case: a[i:j]=x
				Object ro=expArray.getMembers().get(0);
				if(ro instanceof Range) //a[s:e]
				{
					Range range=(Range) ro;
					if(!((lhsType instanceof TypeArray)))
						return translateSingleWordAssignment(stmt,expArray,lhsType,ws,range.start,0,range.end);
					if(staticEvaluation(range.start)!=null && staticEvaluation(range.end)!=null) {
						int start=staticEvaluation(range.start);
						int end=staticEvaluation(range.end);
						if(start/ws==end/ws) //special case: the entire range is contained within a word
							return translateSingleWordAssignment(stmt,expArray,lhsType,ws,range.start,end-start+1);
					}
					return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_bitArrayCopy",Arrays.asList(new Expression[] {
						expArray.getBase(),range.start,range.end,stmt.getRHS(),new ExprConstInt(stmt.getContext(),ws)
					})));

//void SK_bitArrayCopy(int* lhs, int s, int e, int* x, int ws)
//{
//	int aw=s/ws;
//	if(aw==e/ws) {
//		int mask=SK_ONES_SE(s%ws,e%ws);
//		SK_COPYBITS(lhs[aw],mask,x<<(s%ws));
//	}
//	else {
//		int k=s%ws;
//		int l=e-s+1;
//		int nfw=(l+1)/ws;
//		if(k==0) {
//			for(xw=0;xw<nfw;xw++) {
//				lhs[aw++]=x[xw];
//			}
//			int mask=SK_ONES_E(e%ws);
//			SK_COPYBITS(lhs[aw],mask,x[xw]);
//		}
//		else {
//			int kc=ws-k;
//			int mask1=SK_ONES_S(s);
//			int mask2=~mask1;
//			for(xw=0;xw<nfw;xw++) {
//				SK_COPYBITS(lhs[aw],mask1,x[xw]<<k);
//				aw++;
//				SK_COPYBITS(lhs[aw],mask2,x[xw]>>kc);
//			}
//			if(l%ws>k) {
//				SK_COPYBITS(lhs[aw],mask1,x[xw]<<k);
//				aw++;
//				int mask=SK_ONES_E(e%ws);
//				SK_COPYBITS(lhs[aw],mask,x[xw]>>kc);
//			}
//			else {
//				int mask=SK_ONES_S(l%ws);
//				SK_COPYBITS(lhs[aw],mask,x[xw]<<(e%ws-kc));
//			}
//		}
//	}
//}
				}
				else if(ro instanceof RangeLen) //a[s::l]
				{
					RangeLen range=(RangeLen) ro;
					if(!((lhsType instanceof TypeArray)))
						return translateSingleWordAssignment(stmt,expArray,lhsType,ws,range.start,range.len);
					if(staticEvaluation(range.start)!=null) {
						int start=staticEvaluation(range.start);
						int end=start+range.len-1;
						if(start/ws==end/ws) //special case: the entire range is contained within a word
							return translateSingleWordAssignment(stmt,expArray,lhsType,ws,range.start,range.len);
					}
					return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_bitArrayCopy",Arrays.asList(new Expression[] {
							expArray.getBase(),range.start,
							new ExprBinary(stmt.getContext(),ExprBinary.BINOP_ADD,range.start,new ExprConstInt(stmt.getContext(),range.len-1)),
							stmt.getRHS(),new ExprConstInt(stmt.getContext(),ws)
						})));
				}
				else throw new IllegalStateException(); //must be either Range or RangeLen
			}
		}
		else if(stmt.getRHS() instanceof ExprArrayRange)
		{
			final ExprArrayRange expArray=(ExprArrayRange) stmt.getRHS();
			if(expArray.hasSingleIndex()) {
				return super.visitStmtAssign(stmt);
			}
			else {
				Object ro=expArray.getMembers().get(0);
				if(ro instanceof Range) //a[s:e]
				{
					Range range=(Range) ro;
					return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_bitArrayCopyInv",Arrays.asList(new Expression[] {
						stmt.getLHS(),range.start,range.end,expArray.getBase(),new ExprConstInt(stmt.getContext(),ws)
					})));
				}
				else if(ro instanceof RangeLen) //a[s::l]
				{
					RangeLen range=(RangeLen) ro;
//					if(range.len<=ws) {
//						
//					}
					return new StmtExpr(new ExprFunCall(stmt.getContext(),"SK_bitArrayCopyInv",Arrays.asList(new Expression[] {
						stmt.getLHS(),range.start,
						new ExprBinary(stmt.getContext(),ExprBinary.BINOP_ADD,range.start,new ExprConstInt(stmt.getContext(),range.len-1)),
						expArray.getBase(),new ExprConstInt(stmt.getContext(),ws)
					})));
				}
				else throw new IllegalStateException(); //must be either Range or RangeLen
			}
		}
		
		return super.visitStmtAssign(stmt);
	}
	
}
