module SMVParser(
   parseFile
) where
   import DataTypes
   import System.IO
   import Control.Monad
   import Data.Maybe
   import Text.ParserCombinators.Parsec
   import Text.ParserCombinators.Parsec.Expr
   import Text.ParserCombinators.Parsec.Language
   import qualified Text.ParserCombinators.Parsec.Token as Token
      
   languageDef = 
      emptyDef{
               Token.commentLine          = "--",
               Token.identStart           = lower,
               Token.identLetter          = lower,
               Token.reservedNames        = [
                                             "next",
                                             "MODULE",
                                             "DEFINE",
                                             "INIT",
                                             "VAR",
                                             "TRANS",
                                             "TRUE",
                                             "FALSE",
                                             "CTLSPEC",
                                             "FAIRNESS"
                                          ],
               Token.reservedOpNames = [
                                          ":=",
                                          "!",
                                          "&",
                                          "|",
                                          "->",
                                          "<->",
                                          "EG",
                                          "EX",
                                          "EF",
                                          "AG",
                                          "AX",
                                          "AF"
                                       ]
      }

   lexer       = Token.makeTokenParser languageDef
   
   identifier  = Token.identifier      lexer
   reserved    = Token.reserved        lexer
   reservedOp  = Token.reservedOp      lexer
   parens      = Token.parens          lexer
   brackets    = Token.brackets        lexer
   semi        = Token.semi            lexer
   whiteSpace  = Token.whiteSpace      lexer


   -- Se deben de definir operadores distintos para las expresiones Simple y Next, semantica distinta tambien 
   sOperators = [
                    [Prefix  (reservedOp "!"   >> return (SUnary  Not  ))           ],
                    [Infix   (reservedOp "&"   >> return (SBinary And  )) AssocLeft ],
                    [Infix   (reservedOp "|"   >> return (SBinary Or   )) AssocLeft ],
                    [Infix   (reservedOp "->"  >> return (SBinary If   )) AssocRight],
                    [Infix   (reservedOp "<->" >> return (SBinary Iff  )) AssocLeft ]
                  ]
   
   nOperators = [
                    [Prefix  (reservedOp "!"   >> return (NUnary  Not  ))           ],
                    [Infix   (reservedOp "&"   >> return (NBinary And  )) AssocLeft ],
                    [Infix   (reservedOp "|"   >> return (NBinary Or   )) AssocLeft ],
                    [Infix   (reservedOp "->"  >> return (NBinary If   )) AssocRight],
                    [Infix   (reservedOp "<->" >> return (NBinary Iff  )) AssocLeft ]
                  ]
                  
   cOperators = [
                     [Prefix  (reservedOp "!"   >> return (CBUnary   Not   ))           ],
                     [Prefix  (reservedOp "EG"  >> return (CCUnary   EG    ))           ,
                      Prefix  (reservedOp "EX"  >> return (CCUnary   EX    ))           ,
                      Prefix  (reservedOp "EF"  >> return (CCUnary   EF    ))           , 
                      Prefix  (reservedOp "AG"  >> return (CCUnary   AG    ))           , 
                      Prefix  (reservedOp "AX"  >> return (CCUnary   AX    ))           , 
                      Prefix  (reservedOp "AF"  >> return (CCUnary   AF    ))            
                     ],
                     [Infix   (reservedOp "&"   >> return (CBBinary  And   )) AssocLeft ],
                     [Infix   (reservedOp "|"   >> return (CBBinary  Or    )) AssocLeft ],
                     [Infix   (reservedOp "->"  >> return (CBBinary  If    )) AssocRight],
                     [Infix   (reservedOp "<->" >> return (CBBinary  Iff   )) AssocLeft ],
                     [Infix   (reservedOp "<->" >> return (CBBinary  Iff   )) AssocLeft ],
                     [Infix   (reservedOp "EU"  >> return (CCBinary  EU    )) AssocLeft ,
                      Infix   (reservedOp "AU"  >> return (CCBinary  AU    )) AssocLeft 
                     ]
                   ]
            
   programParser :: Parser UProgram
   programParser =   do
                        (UProgram vars def init trans ctlf not) <- uProgramParser
                        opfair                                  <- option (Fair []) fairParser
                        return $ case opfair of
                                    (Fair [])                        ->  error "Error en la especificacion FAIRNESS"
                                    Fair [SVariable (Variable "-1")] ->  UProgram vars def init trans ctlf Nothing
                                    fair                             ->  UProgram vars  def init trans ctlf (Just fair)



   -- Parsea programas completos, sin especificacion de FAIRNESS 
   uProgramParser :: Parser UProgram
   uProgramParser = do
                        vars        <- varSParser
                        (def, init) <- defInitParser
                        trans       <- transParser
                        ctlf        <- ctlFParserC
                        return $ UProgram vars def init trans (CTLS ctlf) Nothing
   

   defInitParser :: Parser (Maybe Define, Init)
   defInitParser = do 
                     tryinit <- option (Init [SVariable (Variable "-1")]) initParser
                     if not (tryinit == (Init [SVariable (Variable "-1")]))
                        then 
                           return $ (Nothing, tryinit)
                        else
                           do
                              trydefine <- defineParser
                              tryinit2  <- initParser
                              return $ ((Just trydefine), tryinit2)

   defineParser :: Parser Define
   defineParser = do
                     reserved "DEFINE" 
                     list <- (endBy1 defExpParser semi)
                     return $ Define list

   defExpParser :: Parser DefineExp
   defExpParser = do
                     var      <- variableParser
                     reservedOp ":="
                     nextexp  <- bNextParser
                     return $ DefineExp var nextexp

   fairParser :: Parser Fair
   fairParser =   eofParser
                  <|> fairnessParser


   eofParser :: Parser Fair
   eofParser = do
                  eof
                  return (Fair [SVariable (Variable "-1")])

   fairnessParser :: Parser Fair
   fairnessParser =  do
                        reserved "FAIRNESS"
                        list <- (endBy1 bSimpleParser semi)
                        return $ Fair list


   
   -- Parsea una secuencia de expresiones simples, dentro de INIT
   initParser :: Parser Init
   initParser = do
                     reserved "INIT"
                     list <- (endBy1 bSimpleParser semi)
                     return $ Init list
   
   -- Parsea una secuencia de expresiones next, dentro de TRANS
   transParser :: Parser Trans
   transParser = do
                     reserved "TRANS"
                     list <- (endBy1 bNextParser semi)
                     return $ Trans list

   -- Parsea expresiones simples (usadas en INIT)
   bSimpleParser :: Parser BSimple
   bSimpleParser = buildExpressionParser sOperators sTerm

   sTerm =      parens bSimpleParser    -- Entre parentesis
            <|> sConstParser            -- Una constante booleana
            <|> sVariableParser         -- Una variable simple


   -- Parsea expresiones next (usadas en TRANS)
   bNextParser :: Parser BNext
   bNextParser = buildExpressionParser nOperators nTerm

   nTerm =      parens bNextParser
            <|> nConstParser 
            <|> nNVariableParser
            <|> nSVariableParser
  
   ctlFParserC :: Parser CTLF         
   ctlFParserC = do
                     reserved "CTLSPEC"
                     ctlf <- ctlFParser
                     semi
                     return ctlf
  
   ctlFParser :: Parser CTLF
   ctlFParser = buildExpressionParser cOperators cTerm

   cTerm =     parens ctlFParser
         <|>  cConstParser
         <|>  cVariableParser
   
   
   {-
      Parsers simples a partir de los lexers
   -}

   -- Parsea constantes booleanas, usadas para formar expresiones simples y complejas
   bConstantParser :: Parser BConstant
   bConstantParser =       (reserved "TRUE" >> return TRUE)
                     <|>   (reserved "FALSE" >> return FALSE)
   

   {-
      Parsers compuestos que envuelven a los simples
   -}

   -- Parsea lista de identificadores
   varSParser :: Parser VarS
   varSParser = do
                     reserved "VAR"
                     list <- (endBy1 variableParser semi) -- separados por punto y coma (semicolon)
                     return $ VarS list

    -- Parsea a los identificadores individualmente
   variableParser :: Parser Variable
   variableParser = liftM Variable identifier -- Conformados por un identificador
   
             
   -- Parsea constantes booleanas dentro de expresiones simples                   
   sConstParser :: Parser BSimple
   sConstParser = do
                     bconstant <- bConstantParser
                     return $ SConst bconstant

   -- Parsea constantes booleanas dentro de expresiones next                   
   nConstParser :: Parser BNext
   nConstParser = do
                    bconstant <- bConstantParser
                    return $ NConst bconstant

   -- Parsea constantes booleanas dentro de expresiones CTL
   cConstParser :: Parser CTLF
   cConstParser = do
                     bconstant <- bConstantParser
                     return $ CConst bconstant

   
   -- Parsea variables (booleanas) dentro de expresiones simples
   sVariableParser :: Parser BSimple
   sVariableParser = do
                        variable <- variableParser
                        return $ SVariable variable
   
   -- Parsea variables (booleanas) dentro de expresiones next    
   nSVariableParser :: Parser BNext
   nSVariableParser = do 
                        variable <- variableParser
                        return $ NSVariable variable

   -- Parsea variables next (booleanas) dentro de expresiones next         
   nNVariableParser :: Parser BNext
   nNVariableParser  = do 
                           reserved "next"
                           nvariable <- parens variableParser
                           return $ NNVariable nvariable

   cVariableParser :: Parser CTLF
   cVariableParser = do 
                        variable <- variableParser
                        return $ CVariable variable





   {-
        **********************************************************************************************
        **********************************************************************************************
        Funciones de prueba hermano
        **********************************************************************************************
        **********************************************************************************************
        **********************************************************************************************
   -}

   -- Simple Expression Parser
   parseBSimple :: String -> BSimple
   parseBSimple string = case parse bSimpleParser "" string of
                                Left e -> error $ show e
                                Right r -> r 

   -- Next Expression Parser
   parseBNext :: String -> BNext
   parseBNext string = case parse bNextParser "" string of
                                Left e -> error $ show e
                                Right r -> r 

   -- CTL Formula Parser
   parseCTLF :: String -> CTLF
   parseCTLF string = case parse ctlFParser "" string of
                                Left e -> error $ show e
                                Right r -> r 

   -- Parsea un programa completo
   parseFile :: String -> IO UProgram
   parseFile file = do 
                        program <- readFile file
                        case parse programParser "" program of
                           Left e   -> print e >> fail "parse error"
                           Right r  -> return r  
