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

package streamit.frontend;
import java.io.BufferedInputStream;
import java.io.BufferedReader;
import java.io.DataInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.LineNumberReader;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

import streamit.frontend.nodes.MakeBodiesBlocks;
import streamit.frontend.nodes.Program;
import streamit.frontend.nodes.TempVarGen;
import streamit.frontend.nodes.Type;
import streamit.frontend.nodes.TypePrimitive;
import streamit.frontend.nodes.TypeStruct;
import streamit.frontend.passes.*;
import streamit.frontend.tojava.ComplexToStruct;
import streamit.frontend.tojava.DoComplexProp;
import streamit.frontend.tojava.EnqueueToFunction;
import streamit.frontend.tojava.InsertIODecls;
import streamit.frontend.tojava.MoveStreamParameters;
import streamit.frontend.tojava.NameAnonymousFunctions;
import streamit.frontend.tosbit.*;

/**
 * Convert StreamIt programs to legal Java code.  This is the main
 * entry point for the StreamIt syntax converter.  Running it as
 * a standalone program reads the list of files provided on the
 * command line and produces equivalent Java code on standard
 * output or the file named in the <tt>--output</tt> command-line
 * parameter.
 *
 * @author  David Maze &lt;dmaze@cag.lcs.mit.edu&gt;
 * @version $Id$
 */
public class ToSBit
{
    public void printUsage()
    {
        System.err.println(
"streamit.frontend.ToJava: StreamIt syntax translator\n" +
"Usage: java streamit.frontend.ToJava [--output out.java] in.str ...\n" +
"\n" +
"Options:\n" +
"  --library      Output code suitable for the Java library\n" +
"  --help         Print this message\n" +
"  --output file  Write output to file, not stdout\n" +
"\n");
    }

    private boolean printHelp = false;
    private boolean libraryFormat = false;
    private String outputFile = null;
    private String sbitPath = null;
    private List<String> inputFiles = new java.util.ArrayList<String>();
    private Map<String, Integer> defines=new HashMap<String, Integer>();
    private int unrollAmt = 8;
    private boolean incremental = false;
    private int incermentalAmt = 0;
    private boolean hasTimeout = false;
    private int timeout = 30;
    private int seed = -1;
    private String resultFile = null;
    private Program beforeUnvectorizing=null;
    private boolean doVectorization=false;
    private boolean outputCFiles=false;
    private String outputCDir="./";
    private boolean outputScript=false;
    private boolean outputTest=false;
    
    public void doOptions(String[] args)
    {
        for (int i = 0; i < args.length; i++)
        {
            if (args[i].equals("--full"))
                ; // Accept but ignore for compatibil5ity
            else if (args[i].equals("--help"))
                printHelp = true;
            else if (args[i].equals("--"))
            {
                // Add all of the remaining args as input files.
                for (i++; i < args.length; i++)
                    inputFiles.add(args[i]);
            }
            else if (args[i].equals("--output"))
                outputFile = args[++i];
            else if (args[i].equals("--ccode"))
            	resultFile = args[++i];
            else if (args[i].equals("--library"))
                libraryFormat = true;
            else if (args[i].equals("--sbitpath"))
                sbitPath = args[++i];
            else if (args[i].equals("-D")) {
                String word = args[++i];
                Integer value = new Integer(args[++i]);
                defines.put(word,value);
            } else if (args[i].equals("--unrollamnt")) {
                Integer value = new Integer(args[++i]);
                unrollAmt = value.intValue(); 
            }else if (args[i].equals("--incremental")) {
                Integer value = new Integer(args[++i]);
                incremental = true;
                incermentalAmt = value.intValue();
            }else if (args[i].equals("--timeout")) {
                Integer value = new Integer(args[++i]);
                hasTimeout = true;
                timeout = value.intValue();
            }else if (args[i].equals("--seed")) {
                Integer value = new Integer(args[++i]);
                seed = value.intValue();
            }else if (args[i].equals("--dovectorization")) {
            	doVectorization=true;
            }else if (args[i].equals("--outputcfiles")) {
            	outputCFiles=true;
            }else if (args[i].equals("--outputdir")) {
                outputCDir = args[++i];
                if(!outputCDir.endsWith("/"))
                	outputCDir=outputCDir+"/";
            }else if (args[i].equals("--outputscript")) {
            	outputScript=true;
            }else if (args[i].equals("--outputtest")) {
            	outputTest=true;
            }
            else
                // Maybe check for unrecognized options.
                inputFiles.add(args[i]);
        }
    }

    /**
     * Generate a Program object that includes built-in structures
     * and streams with code, but no user code.
     *
     * @returns a StreamIt program containing only built-in code
     */
    public static Program emptyProgram()
    {
        List streams = new java.util.ArrayList();
        List<TypeStruct> structs = new java.util.ArrayList<TypeStruct>();
        
        // Complex structure type:
        List<String> fields = new java.util.ArrayList<String>();
        List<Type> ftypes = new java.util.ArrayList<Type>();
        Type floattype = new TypePrimitive(TypePrimitive.TYPE_FLOAT);
        fields.add("real");
        ftypes.add(floattype);
        fields.add("imag");
        ftypes.add(floattype);
        TypeStruct complexStruct =
            new TypeStruct(null, "Complex", fields, ftypes);
        structs.add(complexStruct);
        
        return new Program(null, streams, structs);
    }

    /**
     * Read, parse, and combine all of the StreamIt code in a list of
     * files.  Reads each of the files in <code>inputFiles</code> in
     * turn and runs <code>streamit.frontend.StreamItParserFE</code>
     * over it.  This produces a
     * <code>streamit.frontend.nodes.Program</code> containing lists
     * of structures and streams; combine these into a single
     * <code>streamit.frontend.nodes.Program</code> with all of the
     * structures and streams.
     *
     * @param inputFiles  list of strings naming the files to be read
     * @returns a representation of the entire program, composed of the
     *          code in all of the input files
     * @throws java.io.IOException if an error occurs reading the input
     *         files
     * @throws antlr.RecognitionException if an error occurs parsing
     *         the input files; that is, if the code is syntactically
     *         incorrect
     * @throws antlr.TokenStreamException if an error occurs producing
     *         the input token stream
     */
    public Program parseFiles(List inputFiles)
        throws java.io.IOException,
               antlr.RecognitionException, 
               antlr.TokenStreamException
    {
        Program prog = emptyProgram();
        for (Iterator iter = inputFiles.iterator(); iter.hasNext(); )
        {
            String fileName = (String)iter.next();
            InputStream inStream = new FileInputStream(fileName);
            DataInputStream dis = new DataInputStream(inStream);
            StreamItLex lexer = new StreamItLex(dis);
            StreamItParserFE parser = new StreamItParserFE(lexer);
            parser.setFilename(fileName);
            Program pprog = parser.program();
            if(pprog==null) return null;
            List newStreams, newStructs;
            newStreams = new java.util.ArrayList();
            newStreams.addAll(prog.getStreams());
            newStreams.addAll(pprog.getStreams());
            newStructs = new java.util.ArrayList();
            newStructs.addAll(prog.getStructs());
            newStructs.addAll(pprog.getStructs());
            prog = new Program(null, newStreams, newStructs);
        }
        //invoke post-parse passes
        prog = (Program)prog.accept(new FunctionParamExtension());
        prog = (Program)prog.accept(new ConstantReplacer(defines));
        return prog;
    }

    /**
     * Transform front-end code to have the Java syntax.  Goes through
     * a series of lowering passes to convert an IR tree from the
     * "new" syntax to the "old" Java syntax understood by the main
     * StreamIt compiler.  Conversion directed towards the StreamIt
     * Java library, as opposed to the compiler, has slightly
     * different output, mostly centered around phased filters.
     *
     * @param prog  the complete IR tree to lower
     * @param libraryFormat  true if the program is being converted
     *        to run under the StreamIt Java library
     * @param varGen  object to generate unique temporary variable names
     * @returns the converted IR tree
     */        
    public Program lowerIRToJava(Program prog, boolean libraryFormat,
                                        TempVarGen varGen)
    {
        /* What's the right order for these?  Clearly generic
         * things like MakeBodiesBlocks need to happen first.
         * I don't think there's actually a problem running
         * MoveStreamParameters after DoComplexProp, since
         * this introduces only straight assignments which the
         * Java front-end can handle.  OTOH,
         * MoveStreamParameters introduces references to
         * "this", which doesn't exist. */
        prog = (Program)prog.accept(new MakeBodiesBlocks());
        prog = (Program)prog.accept(new ExtractRightShifts(varGen));
        prog = (Program)prog.accept(new ExtractVectorsInCasts(varGen));
        prog = (Program)prog.accept(new SeparateInitializers());
        prog = (Program)prog.accept(new DisambiguateUnaries(varGen));
        prog = (Program)prog.accept(new NoRefTypes());
        prog = (Program)prog.accept(new FindFreeVariables());
        if (!libraryFormat)
            prog = (Program)prog.accept(new NoticePhasedFilters());
        prog = (Program)prog.accept(new DoComplexProp(varGen));
        prog = (Program)prog.accept(new EliminateArrayRange());
        beforeUnvectorizing = prog;
        prog = (Program)prog.accept(new GenerateCopies(varGen));
        prog = (Program)prog.accept(new ComplexToStruct());
        prog = (Program)prog.accept(new SeparateInitializers());
        prog = (Program)prog.accept(new EnqueueToFunction());
        prog = (Program)prog.accept(new InsertIODecls(libraryFormat));
//        prog = (Program)prog.accept(new InsertInitConstructors(varGen));
        prog = (Program)prog.accept(new MoveStreamParameters());
        prog = (Program)prog.accept(new NameAnonymousFunctions());
        prog = (Program)prog.accept(new AssembleInitializers());
        prog = (Program)prog.accept(new TrimDumbDeadCode());
        return prog;
    }

    public void run(String[] args)
    {
        doOptions(args);
        if (printHelp)
        {
            printUsage();
            return;
        }
        
        Program prog = null;
        Writer outWriter;

        try
        {
            prog = parseFiles(inputFiles);
        }
        catch (Exception e)
        {
            //e.printStackTrace(System.err);
            throw new RuntimeException(e);
        }

        if (prog == null)
        {
            System.err.println("Compilation didn't generate a parse tree.");
            throw new IllegalStateException();
        }
        
        // RenameBitVars is buggy!! prog = (Program)prog.accept(new RenameBitVars());
        if (!SemanticChecker.check(prog))
            throw new IllegalStateException("Semantic check failed");
        prog = (Program)prog.accept(new AssignLoopTypes());
        if (prog == null)
            throw new IllegalStateException();

        TempVarGen varGen = new TempVarGen();
        prog = lowerIRToJava(prog, !libraryFormat, varGen);
        ValueOracle oracle = new ValueOracle();

        try
        {
            if (outputFile != null)
                outWriter = new FileWriter(outputFile);
            else
                outWriter = new OutputStreamWriter(System.out);
            ProduceBooleanFunctions partialEval = new ProduceBooleanFunctions(null, varGen, oracle);
            partialEval.LUNROLL = this.unrollAmt;
            System.out.println("MAX LOOP UNROLLING = " + unrollAmt);
            String javaOut =
                (String)prog.accept( partialEval );
            outWriter.write(javaOut);
            outWriter.flush();
        }
        catch (java.io.IOException e)
        {
            //e.printStackTrace(System.err);
            throw new RuntimeException(e);
        }

        
        boolean worked = solve(oracle);
        if(!worked){
        	throw new RuntimeException("The sketch could not be resolved.");
        }
        
        try{
        	String fname = outputFile + ".tmp";
        	File f = new File(fname);
            FileInputStream fis = new FileInputStream(f); 
            BufferedInputStream bis = new BufferedInputStream(fis);  
            LineNumberReader lir = new LineNumberReader(new InputStreamReader(bis));
        	oracle.loadFromStream(lir);        	
        }
        catch (java.io.IOException e)
        {
            //e.printStackTrace(System.err);
            throw new RuntimeException(e);
        }
        Program noindet = (Program)beforeUnvectorizing.accept(new EliminateStar(oracle, this.unrollAmt));
        if(doVectorization) {
        	noindet=(Program) noindet.accept(new BitVectorPreprocessor(new TempVarGen()));
        	noindet=(Program) noindet.accept(new BitTypeRemover(varGen));
        }
        
    	if(resultFile==null) {
    		resultFile=inputFiles.get(0);
    	}
		if(resultFile.lastIndexOf("/")>=0)
			resultFile=resultFile.substring(resultFile.lastIndexOf("/")+1);
		if(resultFile.lastIndexOf("\\")>=0)
			resultFile=resultFile.substring(resultFile.lastIndexOf("\\")+1);
		if(resultFile.lastIndexOf(".")>=0)
			resultFile=resultFile.substring(0,resultFile.lastIndexOf("."));
        
		String hcode = (String)noindet.accept(new NodesToH(resultFile));
        String ccode = (String)noindet.accept(new NodesToC(varGen,resultFile));
        if(!outputCFiles){
        	System.out.println(hcode);
        	System.out.println(ccode);
        }else{
        	try{
        		outWriter = new FileWriter(outputCDir+resultFile+".h");
            	outWriter.write(hcode);
                outWriter.flush();
                outWriter.close();
        		outWriter = new FileWriter(outputCDir+resultFile+".c");
            	outWriter.write(ccode);
                outWriter.flush();
                outWriter.close();
                if(outputTest) {
                	String testcode=(String)noindet.accept(new NodesToCTest(resultFile));
            		outWriter = new FileWriter(outputCDir+resultFile+"_test.c");
            		outWriter.write(testcode);
                    outWriter.flush();
                    outWriter.close();
                }
                if(outputScript) {
            		outWriter = new FileWriter(outputCDir+"script");
            		outWriter.write("#!/bin/sh\n");
            		if(outputTest)
            			outWriter.write("g++ -o "+resultFile+" "+resultFile+".c "+resultFile+"_test.c\n");
            		else
            			outWriter.write("g++ -c "+resultFile+".c\n");
            		outWriter.write("./"+resultFile+"\n");
            		outWriter.flush();
                    outWriter.close();
                }
            }
            catch (java.io.IOException e){
                throw new RuntimeException(e);
            }
        }
                             
        System.exit(0);
    }
    
    private boolean solve(ValueOracle oracle){
        final List<Boolean> done=new ArrayList<Boolean>();
        
        Thread stopper=null;
        if(hasTimeout){
	        stopper = new Thread() {
				@Override
				public void run()
				{
					try {
						sleep(timeout*60*1000);
					}
					catch (InterruptedException e) {
						e.printStackTrace();
					}
					if(!done.isEmpty()) return;
					System.out.println("Time limit exceeded!");
					System.exit(1);
				}
	        	
	        };
	        stopper.start();
        }
        System.out.println("OFILE = " + outputFile);
        String command = (sbitPath!=null? sbitPath : "") + "SBitII";
        if(this.incremental){
        	boolean isSolved = false;
        	int bits=0;
        	for(bits=1; bits<=this.incermentalAmt; ++bits){
        		System.out.println("TRYING SIZE " + bits);
        		String[] commandLine  = {command , "-overrideCtrls", "" + bits, "-seed", "" + seed  ,outputFile, outputFile + ".tmp"};
    	        boolean ret = runSolver(commandLine, bits);
    	        if(ret){
    	        	isSolved = true;
    	        	break;
    	        }else{
    	        	System.out.println("Size " + bits + " is not enough");
    	        }
        	}
        	if(!isSolved){
	        	System.out.println("The sketch can not be resolved");
	        	return false;
	        }
	        System.out.println("Succeded with " + bits + " bits for integers");	        
        	oracle.capStarSizes(bits);
        }else{
	        String[] commandLine  = {command ,  outputFile, outputFile + ".tmp"};
	        boolean ret = runSolver(commandLine, 0);
	        if(!ret){
	        	System.out.println("The sketch can not be resolved");
	        	return false;
	        }
        }
        done.add(Boolean.TRUE);
        if(hasTimeout){
        	stopper.interrupt();	
        }
        return true;
    }
    
    
    private boolean runSolver(String[] commandLine, int i){
        Runtime rt = Runtime.getRuntime();        
        try
        {	                
	        Process proc = rt.exec(commandLine);   
	        InputStream output = proc.getInputStream();
	        InputStream stdErr = proc.getErrorStream();
	        InputStreamReader isr = new InputStreamReader(output);
	        InputStreamReader errStr = new InputStreamReader(stdErr);
	        BufferedReader br = new BufferedReader(isr);
	        BufferedReader errBr = new BufferedReader(errStr);
	        String line = null;
	        while ( (line = br.readLine()) != null)
	            System.out.println(i + "  " + line);       
	        while ( (line = errBr.readLine()) != null)
	            System.err.println(line);       
	        int exitVal = proc.waitFor();	        
	        System.out.println("Process exitValue: " + exitVal);
	        if(exitVal != 0){	        	
	        	return false;
	        }
        }
        catch (java.io.IOException e)
        {
            //e.printStackTrace(System.err);
            throw new RuntimeException(e);
        }
        catch (InterruptedException e)
        {
            //e.printStackTrace(System.err);
            throw new RuntimeException(e);
        }
        return true;
    }
    
    public static void main(String[] args)
    {
        new ToSBit().run(args);
    }
}

