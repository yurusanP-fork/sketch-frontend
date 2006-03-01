package streamit.frontend.tosbit;

import java.util.*;

import streamit.frontend.nodes.*;
import streamit.frontend.tojava.NodesToJava;

public class NodesToC extends NodesToJava {

	private ArrayList<String> usedMacros=new ArrayList<String>();
	private static HashMap<String,String> macroDefinitions=null;
	
	public NodesToC(boolean libraryFormat, TempVarGen varGen) {
		super(libraryFormat, varGen);
		if(macroDefinitions==null) {
			macroDefinitions=new HashMap<String,String>();
			macroDefinitions.put("SK_BITASSIGN","#define SK_BITASSIGN(a,i,x) a=((a)&(~(1<<(i))))|(((x)&1)<<(i))");
			macroDefinitions.put("SK_ONES","#define SK_ONES(n) ((1<<(n))-1)");
			macroDefinitions.put("SK_ONES_SL","#define SK_ONES_SL(s,l) (SK_ONES(l)<<(s))");
			macroDefinitions.put("SK_ONES_SE","#define SK_ONES_SE(s,e) (SK_ONES((e)+1)^SK_ONES(s))");
			macroDefinitions.put("SK_ONES_S","#define SK_ONES_S(s) (~SK_ONES(s))");
			macroDefinitions.put("SK_ONES_E","#define SK_ONES_E(e) (SK_ONES((e)+1))");
			macroDefinitions.put("SK_COPYBITS","#define SK_COPYBITS(l,m,r) l=((l)&~(m))|((r)&(m))");
			macroDefinitions.put("SK_bitArrayCopy","void SK_bitArrayCopy(int* lhs, int s, int e, int* x, int ws)\n{\n	int aw=s/ws;\n	if(aw==e/ws) {\n		int mask=SK_ONES_SE(s%ws,e%ws);\n		SK_COPYBITS(lhs[aw],mask,x[0]<<(s%ws));\n	}\n	else {\n		int k=s%ws;\n		int l=e-s+1;\n		int nfw=(l+1)/ws;\n		int xw;\n		if(k==0) {\n			for(xw=0;xw<nfw;xw++) {\n				lhs[aw++]=x[xw];\n			}\n			int mask=SK_ONES_E(e%ws);\n			SK_COPYBITS(lhs[aw],mask,x[xw]);\n		}\n		else {\n			int kc=ws-k;\n			int mask1=SK_ONES_S(s);\n			int mask2=~mask1;\n			for(xw=0;xw<nfw;xw++) {\n				SK_COPYBITS(lhs[aw],mask1,x[xw]<<k);\n				aw++;\n				SK_COPYBITS(lhs[aw],mask2,x[xw]>>kc);\n			}\n			if(l%ws>kc) {\n				SK_COPYBITS(lhs[aw],mask1,x[xw]<<k);\n				aw++;\n				int mask=SK_ONES_E(e%ws);\n				SK_COPYBITS(lhs[aw],mask,x[xw]>>kc);\n			}\n			else {\n				int mask=SK_ONES_SE(k,e%ws);\n				SK_COPYBITS(lhs[aw],mask,x[xw]<<k);\n			}\n		}\n	}\n}\n");
		}
	}
	
	private void requireMacro(String m) {
		if(usedMacros.contains(m)) return;
		if(m.startsWith("SK_ONES_")) requireMacro("SK_ONES");
		else if(m.equals("SK_bitArrayCopy")) {
			requireMacro("SK_COPYBITS");
			requireMacro("SK_ONES_SE");
			requireMacro("SK_ONES_S");
			requireMacro("SK_ONES_E");
		}
		assert macroDefinitions.containsKey(m);
		usedMacros.add(m);
	}
	
	@Override
	public Object visitProgram(Program prog)
	{
		String ret=(String)super.visitProgram(prog);
		StringBuffer preamble=new StringBuffer();
		for(Iterator<String> it=usedMacros.iterator();it.hasNext();) {
			preamble.append(macroDefinitions.get(it.next()));
			preamble.append("\n");
		}
		if(preamble.length()==0)
			return ret;
		else {
			preamble.append(ret);
			return preamble.toString();
		}
	}

	public Object visitStreamSpec(StreamSpec spec){
		String result = "";
		ss = spec;
        for (Iterator iter = spec.getFuncs().iterator(); iter.hasNext(); )
        {
            Function oldFunc = (Function)iter.next();            
            result += (String)oldFunc.accept(this);            
        }
        return result;
	}
	
	public Object visitFunction(Function func)
    {
        String result = indent ;
        if (!func.getName().equals(ss.getName()))
            result += convertType(func.getReturnType()) + " ";
        result += func.getName();
        String prefix = null;
        if (func.getCls() == Function.FUNC_INIT) prefix = "final";
        result += doParams(func.getParams(), prefix) + " ";
        result += (String)func.getBody().accept(this);
        result += "\n";
        return result;
    }
	

    public String doParams(List params, String prefix)
    {
        String result = "(";
        boolean first = true;
        for (Iterator iter = params.iterator(); iter.hasNext(); )
        {
            Parameter param = (Parameter)iter.next();
            Type type = param.getType();
            String postFix = "";
            if(type instanceof TypeArray){
            	postFix = "*";
            	type = ((TypeArray)type).getBase();
            }
            
            if (!first) result += ", ";
            if (prefix != null) result += prefix + " ";
            result += convertType(type) + postFix;
            if(param.getType() instanceof TypePrimitive){
            	result += "&";
            }
            result += " ";
            result += param.getName();
            first = false;
        }
        result += ")";
        return result;
    }

    public Object visitStmtVarDecl(StmtVarDecl stmt)
    {
        String result = "";
        Type type = stmt.getType(0);
        String postFix = "";
        if(type instanceof TypeArray){
        	postFix = "[" + ((TypeArray)type).getLength() +  "]";
        	type = ((TypeArray)type).getBase();
        }
        result += convertType(type) +  " ";
        for (int i = 0; i < stmt.getNumVars(); i++)
        {
            if (i > 0)
                result += ", ";
            result += stmt.getName(i)+ postFix ;
            if (stmt.getInit(i) != null)
                result += " = " + (String)stmt.getInit(i).accept(this);
        }
        return result;
    }
	
	public Object visitExprFunCall(ExprFunCall exp)
    {
		String result = "";
        String name = exp.getName();
        if(macroDefinitions.containsKey(name)) {
        	requireMacro(name);
        }
        result = name + "(";         
        boolean first = true;
        for (Iterator iter = exp.getParams().iterator(); iter.hasNext(); )
        {
            Expression param = (Expression)iter.next();
            if (!first) result += ", ";
            first = false;
            result += (String)param.accept(this);
        }
        result += ")";
        return result;        
    }
	
	
    public Object visitStmtLoop(StmtLoop stmt)
    {
    	
    	String result ;
    	String itNum = this.varGen.nextVar();
    	String var = this.varGen.nextVar();
    	result = itNum + " = " + stmt.getIter().accept(this) + "; \n";
    	result += indent + "for (int " + var + " = 0; ";
    	result += var + " < " +  itNum + "; ++" + var;         
        result += ") ";
        result += (String)stmt.getBody().accept(this);
        return result;
    }

	@Override
	public String convertType(Type type)
	{
		if(type instanceof TypePrimitive) {
			switch(((TypePrimitive)type).getType()) {
				case TypePrimitive.TYPE_INT8:  return "char";
				case TypePrimitive.TYPE_INT16: return "short int";
				case TypePrimitive.TYPE_INT32: return "int";
				case TypePrimitive.TYPE_INT64: return "long long";
				case TypePrimitive.TYPE_BIT:   return "int";
			}
		}
		return super.convertType(type);
	}

}
