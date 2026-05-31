%{
#include <iostream>
#include <string>
#include <vector>
#include <map>

#define YYSTYPE atributos

using namespace std;

int var_temp_qnt = 0;
int label_qnt = 0;
vector<pair<string, string>> temporarios;
int linha = 1;
string codigo_gerado;

// Structs
struct atributos
{
    string label;
    string traducao;
    string tipo;
};

struct Simbolo {
    string tipo;
    string temp;
};

// Pilha de escopos (Contexto)
vector<map<string, Simbolo>> pilha_tabelas(1);
vector<string> switch_expr_stack;
vector<string> switch_tipo_stack;
vector<string> stack_fim;
vector<string> stack_continue;

// Funções
int yylex(void);
void yyerror(string);
string gentempcode(string tipo);
string declaraTemp();

// Funções auxiliares para buscar variáveis na pilha de escopos
bool declarada_no_escopo_atual(string id) {
    return pilha_tabelas.back().count(id) > 0;
}

bool declarada(string id) {
    for (int i = pilha_tabelas.size() - 1; i >= 0; i--) {
        if (pilha_tabelas[i].count(id) > 0) return true;
    }
    return false;
}

Simbolo obter_simbolo(string id) {
    for (int i = pilha_tabelas.size() - 1; i >= 0; i--) {
        if (pilha_tabelas[i].count(id) > 0) return pilha_tabelas[i][id];
    }
    return Simbolo{"erro", ""};
}

void inserir_simbolo(string id, string tipo, string temp) {
    pilha_tabelas.back()[id] = Simbolo{tipo, temp};
}

void atualizar_temp_simbolo(string id, string temp) {
    for (int i = pilha_tabelas.size() - 1; i >= 0; i--) {
        if (pilha_tabelas[i].count(id) > 0) {
            pilha_tabelas[i][id].temp = temp;
            return;
        }
    }
}

string gen_label() {
    label_qnt++;
    return "L" + to_string(label_qnt);
}

string obter_formatador(string tipo) {
    if (tipo == "int" || tipo == "bool") return "%d";
    if (tipo == "float") return "%f";
    if (tipo == "char") return "%c";
    if (tipo == "string") return "%s";
    return "";
}

string maior_tipo(string t1, string t2) {
    if (t1 == "bool" || t2 == "bool") return "erro";
    if (t1 == "float" || t2 == "float") return "float";
    if (t1 == "int"   || t2 == "int")   return "int";
    return "char";
}

string converter(string origem, string destino, string label, string &novas_instrucoes) {
    if (origem == destino) return label;
    
    // garante nao converter bools
    if (origem == "bool" || destino == "bool") {
        return "ERRO_TIPO";
    }
    
    string temp = gentempcode(destino);
    novas_instrucoes += "\t" + temp + " = (" + destino + ") " + label + ";\n";
    return temp;
}

atributos op_aritmetico(atributos e1, atributos e2, string op) {
    string t = maior_tipo(e1.tipo, e2.tipo);
    if (t == "erro") {
        yyerror("Operacao invalida envolvendo tipos booleanos.");
    }
    string conversoes = "";
    string l1 = converter(e1.tipo, t, e1.label, conversoes);
    string l2 = converter(e2.tipo, t, e2.label, conversoes);
    atributos res;
    res.tipo = t;
    res.label = gentempcode(t);
    res.traducao = e1.traducao + e2.traducao + conversoes +
                   "\t" + res.label + " = " + l1 + " " + op + " " + l2 + ";\n";
    return res;
}

atributos op_relacional(atributos e1, atributos e2, string op) {
    string t = maior_tipo(e1.tipo, e2.tipo);
    if (t == "erro") {
        yyerror("Operacao relacional invalida envolvendo tipos booleanos.");
    }
    string conversoes = "";
    string l1 = converter(e1.tipo, t, e1.label, conversoes);
    string l2 = converter(e2.tipo, t, e2.label, conversoes);
    atributos res;
    res.tipo = "bool";
    res.label = gentempcode("bool");
    res.traducao = e1.traducao + e2.traducao + conversoes +
                   "\t" + res.label + " = " + l1 + " " + op + " " + l2 + ";\n";
    return res;
}

string montar_programa(string traducao_interna) {
    string prog = "/*Compilador FOCA*/\n"
                  "#include <stdio.h>\n"
                  "#include <string.h>\n"
                  "int main(void) {\n";
                  
    prog += declaraTemp();
    
    prog += "\n" + traducao_interna + "\treturn 0;\n}\n";
    return prog;
}
%}

%token TK_NUM TK_FLOAT TK_ID TK_CHAR TK_STRING
%token INT FLOAT_TYPE CHAR DOUBLE BOOL_TYPE STRING
%token FOR WHILE DO RETURN CONTINUE
%token EQ NE LE GE
%token AND OR TK_BOOL
%token NOT
%token PRINT SCAN PRINTLN
%token IF ELSE SWITCH CASE DEFAULT BREAK

%start S

%left OR
%left AND
%left EQ NE
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right NOT
%right PREC_CAST

%%

S           : E        { codigo_gerado = montar_programa($1.traducao); }
            | COMANDOS { codigo_gerado = montar_programa($1.traducao); }
            ;

BLOCO_INICIO : '{' { pilha_tabelas.push_back(map<string, Simbolo>()); } 
             ;

BLOCO_FIM    : '}' { pilha_tabelas.pop_back(); } 
             ;

BLOCO        : BLOCO_INICIO COMANDOS BLOCO_FIM  {$$.traducao = $2.traducao; }
             | BLOCO_INICIO BLOCO_FIM {$$.traducao = ""; }
             ;

COMANDOS    : COMANDO COMANDOS
            {
                $$.traducao = $1.traducao + $2.traducao;
            }
            | COMANDO
            {
                $$.traducao = $1.traducao;
            }
            ;

COMANDO     : DECL ';' {$$.traducao = $1.traducao;}
            | BLOCO { $$.traducao = $1.traducao; }
            | IF '(' E ')' BLOCO
            {
                if ($3.tipo != "bool") {
                    yyerror("A condicao do IF deve resultar em um booleano.");
                }
                
                string label_fim = gen_label();
                
                $$.traducao = $3.traducao +
                              "\tif(!" + $3.label + ") goto " + label_fim + ";\n" +
                              $5.traducao +
                              "\t" + label_fim + ":\n";
            }
            | IF '(' E ')' BLOCO ELSE BLOCO
            {
                if ($3.tipo != "bool") {
                    yyerror("A condicao do IF deve resultar em um booleano.");
                }
                
                string label_else = gen_label();
                string label_fim = gen_label();
                
                $$.traducao = $3.traducao +
                              "\tif(!" + $3.label + ") goto " + label_else + ";\n" +
                              $5.traducao +
                              "\tgoto " + label_fim + ";\n" +
                              "\t" + label_else + ":\n" +
                              $7.traducao +
                              "\t" + label_fim + ":\n";
            }
            | SWITCH '(' E ')'
            {
                  // Salva a variavel e o tipo que estao sendo testados
                  switch_expr_stack.push_back($3.label);
                  switch_tipo_stack.push_back($3.tipo);
                  // Gera e salva a label de saida (para onde o break pula)
                  stack_fim.push_back(gen_label());
            }
              '{' CASOS '}'
            {
                  string l_fim = stack_fim.back();
                  
                  // Limpa as pilhas quando o switch termina
                  switch_expr_stack.pop_back();
                  switch_tipo_stack.pop_back();
                  stack_fim.pop_back();
                  
                  // Junta tudo e bota a label de fim no final
                  $$.traducao = $3.traducao + $7.traducao + "\t" + l_fim + ":\n";
            }
            | BREAK ';'
            {
                  if(stack_fim.empty()) {
                      yyerror("O comando 'break' deve estar dentro de um switch ou laco.");
                  }
                  // O break vira simplesmente um pulo para o final da estrutura
                  $$.traducao = "\tgoto " + stack_fim.back() + ";\n";
            }
            | WHILE '(' 
              {
                  // Salva os labels de inicio (continue) e fim (break) na pilha
                  stack_continue.push_back(gen_label());
                  stack_fim.push_back(gen_label());
              }
              E ')' BLOCO
              {
                  if ($4.tipo != "bool") yyerror("A condicao do while deve ser bool.");
                  
                  string l_inicio = stack_continue.back(); stack_continue.pop_back();
                  string l_fim = stack_fim.back(); stack_fim.pop_back();
                  
                  $$.traducao = "\t" + l_inicio + ":\n" +
                                $4.traducao +
                                "\tif(!" + $4.label + ") goto " + l_fim + ";\n" +
                                $6.traducao +
                                "\tgoto " + l_inicio + ";\n" +
                                "\t" + l_fim + ":\n";
              }
            | DO
              {
                  stack_continue.push_back(gen_label()); // Label para o continue (vai para a condicao)
                  stack_fim.push_back(gen_label());      // Label para o break
              }
              BLOCO WHILE '(' E ')' ';'
              {
                  if ($6.tipo != "bool") yyerror("A condicao do do/while deve ser bool.");
                  
                  string l_condicao = stack_continue.back(); stack_continue.pop_back();
                  string l_fim = stack_fim.back(); stack_fim.pop_back();
                  string l_inicio = gen_label(); 
                  
                  $$.traducao = "\t" + l_inicio + ":\n" +
                                $3.traducao +
                                "\t" + l_condicao + ":\n" + // Continue pula pra ca!
                                $6.traducao +
                                "\tif(" + $6.label + ") goto " + l_inicio + ";\n" +
                                "\t" + l_fim + ":\n";
              }
            | FOR '(' OPT_ATRIB_FOR ';' OPT_E ';' OPT_ATRIB_FOR ')'
              {
                  stack_continue.push_back(gen_label()); 
                  stack_fim.push_back(gen_label());      
              }
              BLOCO
              {
                  if ($5.tipo != "bool") yyerror("Condicao do for deve ser bool");

                  string l_incremento = stack_continue.back(); stack_continue.pop_back();
                  string l_fim = stack_fim.back(); stack_fim.pop_back();
                  string l_inicio = gen_label(); 

                  // $3 = Inicializacao opcional 1 
                  // $5 = Condicao opcional 2 
                  // $7 = Incremento opcional 3 
                  // $10 = Bloco de codigo {}

                  $$.traducao = $3.traducao +
                                "\t" + l_inicio + ":\n" +
                                $5.traducao +
                                "\tif(!" + $5.label + ") goto " + l_fim + ";\n" +
                                $10.traducao +
                                "\t" + l_incremento + ":\n" +
                                $7.traducao +
                                "\tgoto " + l_inicio + ";\n" +
                                "\t" + l_fim + ":\n";
              }
            | CONTINUE ';'
              {
                  if(stack_continue.empty()) {
                      yyerror("O comando 'continue' deve estar dentro de um laco de repeticao.");
                  }
                  // Pula para a etiqueta de continuacao mais proxima da pilha
                  $$.traducao = "\tgoto " + stack_continue.back() + ";\n";
              }
            | TIPO TK_ID '=' E ';'
            {
                if(declarada_no_escopo_atual($2.label)) {
                    yyerror("Variavel ja declarada neste escopo");
                }

                string tipo_id = $1.tipo; 
                string temp_id = gentempcode(tipo_id);
                inserir_simbolo($2.label, tipo_id, temp_id);

                if(tipo_id == "string") {
                    $$.traducao = $4.traducao +
                                  "\tstrcpy(" + temp_id + ", " + $4.label + ");\n";
                } else {
                    string conversoes = "";
                    string label_final = converter($4.tipo, tipo_id, $4.label, conversoes);

                    if (label_final == "ERRO_TIPO") {
                        yyerror("Tipos incompativeis: nao e possivel converter para bool.");
                    }

                    $$.traducao = $4.traducao + conversoes +
                                  "\t" + temp_id + " = " + label_final + ";\n";
                }
            }
            | TK_ID '=' E ';'
            {
                if(!declarada($1.label)) {
                    yyerror("Variavel nao declarada");
                }
                
                Simbolo var = obter_simbolo($1.label);
                
                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                if(var.tipo == "string") {
                    $$.traducao = $3.traducao +
                                  "\tstrcpy(" + var.temp + ", " + $3.label + ");\n";
                } else {
                    string conversoes = "";
                    string label_final = converter($3.tipo, var.tipo, $3.label, conversoes);

                    if (label_final == "ERRO_TIPO") {
                        yyerror("Tipos incompativeis.");
                    }

                    $$.traducao = $3.traducao + conversoes +
                                  "\t" + var.temp + " = " + label_final + ";\n";
                }
            }
            | TK_ID '=' E
            {
                // Lida com declaracoes implicitas e sem ponto-e-virgula
                if(!declarada($1.label)) {
                    inserir_simbolo($1.label, $3.tipo, "");
                }

                Simbolo var = obter_simbolo($1.label);

                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                if(var.tipo == "string") {
                    $$.traducao = $3.traducao +
                                  "\tstrcpy(" + var.temp + ", " + $3.label + ");\n";
                } else {
                    $$.traducao = $3.traducao +
                                  "\t" + var.temp + " = " + $3.label + ";\n";
                }
            }
            | PRINT '(' ARGS_PRINT ')' ';'
            {
                $$.traducao = $3.traducao;
            }
            | PRINTLN '(' ARGS_PRINT ')' ';'
            {
                $$.traducao = $3.traducao +
                              "\tprintf(\"\\n\");\n";
            }
            | SCAN '(' ARGS_SCAN ')' ';'
            {
                // A regra ARGS_SCAN ja vai ter montado todos os scanf necessarios
                $$.traducao = $3.traducao;
            }
            ;

ARGS_PRINT  : ARGS_PRINT ',' E
            {
                string formato = obter_formatador($3.tipo);
                
                // Mantem a execucao anterior ($1), calcula a expressao atual ($3) e imprime
                $$.traducao = $1.traducao + $3.traducao +
                              "\tprintf(\"" + formato + "\", " + $3.label + ");\n";
            }
            | E
            {
                string formato = obter_formatador($1.tipo);
                
                // Base da recursao (primeiro argumento)
                $$.traducao = $1.traducao +
                              "\tprintf(\"" + formato + "\", " + $1.label + ");\n";
            }
            ;

ARGS_SCAN   : ARGS_SCAN ',' TK_ID
            {
                if(!declarada($3.label)) {
                    yyerror("Variavel nao declarada para leitura");
                }
                
                Simbolo var = obter_simbolo($3.label);
                
                if (var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($3.label, var.temp);
                }
                
                string comercial = (var.tipo == "string") ? "" : "&";
                string formato = obter_formatador(var.tipo);
                
                // Concatena a leitura das variaveis anteriores com a atual
                $$.traducao = $1.traducao + 
                              "\tscanf(\"" + formato + "\", " + comercial + var.temp + ");\n";
            }
            | TK_ID
            {
                if(!declarada($1.label)) {
                    yyerror("Variavel nao declarada para leitura");
                }
                
                Simbolo var = obter_simbolo($1.label);
                
                if (var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }
                
                string comercial = (var.tipo == "string") ? "" : "&";
                string formato = obter_formatador(var.tipo);
                
                // Base da recursao (primeira variavel)
                $$.traducao = "\tscanf(\"" + formato + "\", " + comercial + var.temp + ");\n";
            }
            ;
CASOS       : CASO CASOS
              {
                  $$.traducao = $1.traducao + $2.traducao;
              }
            | CASO
              {
                  $$.traducao = $1.traducao;
              }
            ;
ATRIB_FOR   : TK_ID '=' E
            {
                // Mesma logica de declaracao implicita que voce ja usa
                if(!declarada($1.label)) {
                    inserir_simbolo($1.label, $3.tipo, "");
                }

                Simbolo var = obter_simbolo($1.label);

                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                if(var.tipo == "string") {
                    $$.traducao = $3.traducao +
                                  "\tstrcpy(" + var.temp + ", " + $3.label + ");\n";
                } else {
                    $$.traducao = $3.traducao +
                                  "\t" + var.temp + " = " + $3.label + ";\n";
                }
            }
            ;
OPT_ATRIB_FOR : ATRIB_FOR 
              { 
                  $$.traducao = $1.traducao; 
              }
              |
              { 
                  $$.traducao = ""; 
              }
              ;

OPT_E         : E 
              { 
                  $$ = $1; 
              }
              |
              { 
                  // Se fizer for(;;),
                  $$.traducao = ""; 
                  $$.label = "1"; 
                  $$.tipo = "bool"; 
              }
              ;

CASO        : CASE E ':' COMANDOS
              {
                  // Resgata quem e o switch alvo
                  string var_label = switch_expr_stack.back();
                  string var_tipo = switch_tipo_stack.back();
                  string l_fim = stack_fim.back();
                  string l_next = gen_label(); // Se errar esse case, pula pro proximo
                  string temp_cond = gentempcode("bool");

                  if (var_tipo == "string" || $2.tipo == "string") {
                      yyerror("O switch ainda nao suporta comparacao de strings.");
                  }

                  // Monta o "if" desse caso
                  $$.traducao = $2.traducao +
                                "\t" + temp_cond + " = " + var_label + " == " + $2.label + ";\n" +
                                "\tif(!" + temp_cond + ") goto " + l_next + ";\n" +
                                $4.traducao +
                                "\tgoto " + l_fim + ";\n" + // Break automatico no fim do case
                                "\t" + l_next + ":\n";
              }
            | DEFAULT ':' COMANDOS
              {
                  // O default e executado direto se sobrar pra ele
                  $$.traducao = $3.traducao;
              }
            ;


DECL        : TIPO TK_ID
            {
                if(declarada_no_escopo_atual($2.label)) {
                    yyerror("Variavel ja declarada neste escopo");
                }

                inserir_simbolo($2.label, $1.tipo, "");

                $$.traducao = "";
            }
            ;

TIPO        : INT {$$.tipo = "int";}
            | FLOAT_TYPE{ $$.tipo = "float";}
            | CHAR {$$.tipo = "char";}
            | BOOL_TYPE {$$.tipo = "bool";}
            | STRING {$$.tipo = "string";}
            ;
                        /* Aritmetico e String Concat */
E           : E '+' E    
            {
                if($1.tipo == "string" && $3.tipo == "string"){
                    $$.tipo = "string";
                    $$.label = gentempcode("string");

                    $$.traducao = $1.traducao + $3.traducao +
                    "\tstrcpy("+ $$.label + ", " + $1.label + ");\n" + 
                    "\tstrcat("+ $$.label +", " + $3.label + ");\n";
                }else if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Concatenação exige duas strings.");
                }
                else { $$ = op_aritmetico($1, $3, "+"); }
            }
            | E '-' E    
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Essa operação não é possível com strings.");
                }else{ $$ = op_aritmetico($1, $3, "-");} 
            }
            | E '*' E    
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Essa operação não é possível com strings.");
                }else{ $$ = op_aritmetico($1, $3, "*"); }
            }
            | E '/' E    
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Essa operação não é possível com strings.");
                }else{ $$ = op_aritmetico($1, $3, "/"); }
            }
            | E '%' E    // resto
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Essa operacao nao e possivel com strings.");
                }else{ $$ = op_aritmetico($1, $3, "%"); }
            }

            /* Relacionais */
            | E '<' E    
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, "<"); }
            }
            | E '>' E    
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, ">"); }
            }
            | E LE E     
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, "<="); }
            }
            | E GE E     
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, ">="); }
            }
            | E EQ E     
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, "=="); }
            }
            | E NE E     
            {
                if($1.tipo == "string" || $3.tipo == "string"){
                    yyerror("Comparação entre strings não permitida.");
                }else{ $$ = op_relacional($1, $3, "!="); }
            }
            | E AND E
            {
                if ($1.tipo != "bool" || $3.tipo != "bool") {
                    yyerror("Operadores logicos (&&, ||) exigem operandos bool.");
                }
                $$.tipo = "bool";
                $$.label = gentempcode("bool");
                $$.traducao = $1.traducao + $3.traducao + 
                    "\t" + $$.label + " = " + $1.label + " && " + $3.label + ";\n";
            }
            | E OR E
            {
                if ($1.tipo != "bool" || $3.tipo != "bool") {
                    yyerror("Operadores logicos (&&, ||) exigem operandos bool.");
                }

                $$.tipo = "bool";
                $$.label = gentempcode("bool");
                $$.traducao = $1.traducao + $3.traducao + 
                              "\t" + $$.label + " = " + $1.label + " || " + $3.label + ";\n";
            }
            | NOT E
            {
                if ($2.tipo != "bool") {
                    yyerror("O operador de negacao (!) exige um operando bool.");
                }
                $$.tipo = "bool";
                $$.label = gentempcode("bool");
                $$.traducao = $2.traducao + 
                              "\t" + $$.label + " = !" + $2.label + ";\n";
            }
            | '(' TIPO ')' E %prec PREC_CAST
            {
                string temp_copia = gentempcode($4.tipo);
                string temp_cast  = gentempcode($2.tipo);
                $$.tipo  = $2.tipo;
                $$.label = temp_cast;
                
                // Impede que o C receba um cast (bool)
                string tipo_c = ($2.tipo == "bool") ? "int" : $2.tipo;
                
                $$.traducao = $4.traducao +
                    "\t" + temp_copia + " = " + $4.label + ";\n" +
                    "\t" + temp_cast  + " = (" + tipo_c + ") " + temp_copia + ";\n";
            }
            | '(' E ')'
            {
                $$.label = $2.label;
                $$.traducao = $2.traducao;
                $$.tipo = $2.tipo;
            }
            | TK_FLOAT
            {
                $$.tipo = "float";
                $$.label = gentempcode("float");
                $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n";
            }
            | TK_NUM
            {   
                $$.tipo = "int";
                $$.label = gentempcode("int");
                $$.traducao = "\t" + $$.label + " = " + $1.label + ";\n";
            }
            | TK_CHAR
            {
                $$.tipo = "char";
                $$.label = $1.label;
                $$.traducao = "";
            }
            | TK_BOOL
            {
                $$.tipo = "bool";
                
                // Converte os literais para inteiros que o C entenda nativamente
                if ($1.label == "true" || $1.label == "TRUE") {
                    $$.label = "1";
                } else if ($1.label == "false" || $1.label == "FALSE") {
                    $$.label = "0";
                } else {
                    $$.label = $1.label; // Caso o lexico ja envie 1 ou 0
                }
                
                $$.traducao = "";
            }
            | TK_STRING
            {
                $$.tipo = "string";
                $$.label = $1.label;
                $$.traducao = "";
            }
            | TK_ID
            {
                if(!declarada($1.label))
                {
                    // Comportamento original: declara implicitamente como int
                    inserir_simbolo($1.label, "int", "");
                }

                Simbolo var = obter_simbolo($1.label);
                
                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                $$.tipo = var.tipo;
                $$.label = var.temp;
                $$.traducao = "";
            }
            ;

%%

#include "lex.yy.c"

int yyparse();

string declaraTemp(){
    string s;

    for (auto &t : temporarios) {
        if(t.second == "string"){
            s += "\tchar " + t.first + "[1024];\n";
        }
        else if(t.second == "bool"){
            s += "\tint " + t.first + ";\n";
        }
        else{
            s += "\t" + t.second + " " + t.first + ";\n";
        }
    }

    return s;
}

string gentempcode(string tipo)
{
    var_temp_qnt++;
    string nome = "t" + to_string(var_temp_qnt);
    temporarios.push_back({nome, tipo});
    return nome;
}

int main(int argc, char* argv[])
{
    var_temp_qnt = 0;

    if (yyparse() == 0)
        cout << codigo_gerado;

    return 0;
}

void yyerror(string MSG)
{
    cerr << "Erro na linha " << linha << ": " << MSG << endl;
    exit(1);
}