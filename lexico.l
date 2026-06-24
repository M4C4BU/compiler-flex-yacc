%{
#include "y.tab.h"
#include <string>
#include <stdio.h>

extern int linha;
%}

%option noyywrap

LETRA      [a-zA-Z_]
DIGITO     [0-9]

ID         {LETRA}({LETRA}|{DIGITO})*
NUM        {DIGITO}+
FLOAT      {DIGITO}+\.{DIGITO}*([eE][+-]?{DIGITO}+)?

%%

[ \t\r]+
\n          { linha++;}

"//".*
"/*"([^*]|\*+[^*/])*\*+"/"

"int"       { return INT; }
"float"     { return FLOAT_TYPE; }
"char"      { return CHAR; }
"double"    { return DOUBLE; }
"bool"      { return BOOL_TYPE; }
"string"    { return STRING; }
"void"      { return VOID_TYPE; }
"var"       { return VAR; }

"print"     { return PRINT; }
"println"   { return PRINTLN; }
"scan"      { return SCAN; }
"sqrt"      { return SQRT; }

"if"        { return IF; }
"else"      { return ELSE; }
"for"       { return FOR; }
"foreach"   { return FOREACH; }
"in"        { return IN; }
"while"     { return WHILE; }
"do"        { return DO; }
"return"    { return RETURN; }
"continue"  { return CONTINUE; }

"switch"    { return SWITCH; }
"case"      { return CASE; }
"default"   { return DEFAULT; }
"break"     { return BREAK; }
":"         { return ':'; }

"=="        { return EQ; }
"!="        { return NE; }
"<="        { return LE; }
">="        { return GE; }
"&&"        { return AND; }
"||"        { return OR; }
"!"         { return NOT; }

"++"        { return INC; }
"--"        { return DEC; }
"+="        { return PLUS_EQ; }
"-="        { return MINUS_EQ; }
"**"        { return POW; }
"*="        { return MUL_EQ; }
"/="        { return DIV_EQ; }
"%="        { return MOD_EQ; }

"+"         { return '+'; }
"-"         { return '-'; }
"*"         { return '*'; }
"/"         { return '/'; }
"%"         { return '%'; }
"<"         { return '<'; }
">"         { return '>'; }
"="         { return '='; }
"("         { return '('; }
")"         { return ')'; }
"{"         { return '{'; }
"}"         { return '}'; }
";"         { return ';'; }
","         { return ','; }
"["         { return '['; }
"]"         { return ']'; }

{FLOAT}     { yylval.label = yytext; return TK_FLOAT; }
{NUM}       { yylval.label = yytext; return TK_NUM; }
\'[^\']\'   { yylval.label = yytext; return TK_CHAR; }
\"([^\"\n]|\\.)*\"  { yylval.label = yytext; return TK_STRING;}
"true"      { yylval.label = "1"; return TK_BOOL; }
"false"     { yylval.label = "0"; return TK_BOOL; }

{ID}        { yylval.label = yytext; return TK_ID; }

.           { printf("Erro léxico na linha %d: caractere invalido '%s'\n", linha, yytext); }

%%
