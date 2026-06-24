%{
#include <iostream>
#include <string>
#include <vector>
#include <map>

#define YYSTYPE atributos

using namespace std;

int var_temp_qnt = 0;
int label_qnt = 0;
struct TempVar { string nome; string tipo; int array_size = 0; };
vector<TempVar> temporarios;
int linha = 1;
string codigo_gerado;

struct InitElem { string label; string code; string tipo; };
vector<vector<InitElem>> g_init_matrix;

// Structs
struct atributos
{
    string label;
    string traducao;
    string tipo;
    string kind;
    string arr_id;   // identificador original do array
    string arr_temp; // variavel C que representa o array (ex: "t5")
    int    ndim = 0; // dimensoes acumuladas no Elist
    vector<int> dims;// tamanhos das dimensoes (regra DIMS)
};

struct Simbolo {
    string tipo;
    string temp;
    vector<int> dims; // vazio=escalar, {10}=1D, {3,4}=2D
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
string gentemparray(string tipo, int size);
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
    Simbolo s; s.tipo = "erro"; return s;
}

void inserir_simbolo(string id, string tipo, string temp) {
    Simbolo s; s.tipo = tipo; s.temp = temp;
    pilha_tabelas.back()[id] = s;
}

void inserir_simbolo_array(string id, string tipo, string temp, vector<int> dims) {
    Simbolo s; s.tipo = tipo; s.temp = temp; s.dims = dims;
    pilha_tabelas.back()[id] = s;
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
    if (tipo == "int") return "%d";
    if (tipo == "float") return "%f";
    if (tipo == "char") return "%c";
    if (tipo == "string") return "%s";
    return "";
}

string gerar_printf(string tipo, string label) {
    if (tipo == "bool")
        return "\tprintf(\"%s\", " + label + " ? \"true\" : \"false\");\n";
    return "\tprintf(\"" + obter_formatador(tipo) + "\", " + label + ");\n";
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
string atribuir_string(string destino, atributos origem) {
    string cod = origem.traducao;
    cod += "\tif(" + destino + ") free(" + destino + ");\n";

    if (origem.kind == "temp") {
        cod += "\t" + destino + " = " + origem.label + ";\n";
    } else {
        cod += "\t" + destino + " = malloc(contar_chars(" + origem.label + ") + 1);\n";
        cod += "\tstrcpy(" + destino + ", " + origem.label + ");\n";
    }
    return cod;
}

string montar_programa(string traducao_interna) {
    string prog = "/*Compilador FOCA*/\n"
                  "#include <stdio.h>\n"
                  "#include <string.h>\n"
                  "#include <stdlib.h>\n\n"
                  "int contar_chars(char* s){\n"
                  "\tint i = 0;\n"
                  "\tchar t0;\n"
                  "\tint t1;\n"
                  "\tL_cc_loop:\n"
                  "\tt0 = s[i];\n"
                  "\tt1 = t0 == '\\0';\n"
                  "\tif(t1) goto L_cc_fim;\n"
                  "\ti = i + 1;\n"
                  "\tgoto L_cc_loop;\n"
                  "\tL_cc_fim:\n"
                  "\treturn i;\n"
                  "}\n\n"
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
%token INC DEC
%token PLUS_EQ MINUS_EQ MUL_EQ DIV_EQ MOD_EQ

%start S

%left OR
%left AND
%left EQ NE
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/' '%'
%right NOT
%right PREC_CAST
%right UMINUS UPLUS
%right INC DEC

%%

S           : E        { codigo_gerado = montar_programa($1.traducao); }
            | COMANDOS { codigo_gerado = montar_programa($1.traducao); }
            ;

BLOCO_INICIO : '{' { pilha_tabelas.push_back(map<string, Simbolo>()); } 
             ;

BLOCO_FIM    : '}' 
             {
                 // Ao sair do escopo, libera qualquer string declarada dentro dele.
                 string limpeza;
                 for (auto &par : pilha_tabelas.back()) {
                     if (par.second.tipo == "string" && par.second.temp != "") {
                         limpeza += "\tif(" + par.second.temp + ") { free(" + par.second.temp +
                                    "); " + par.second.temp + " = NULL; }\n";
                     }
                 }
                 pilha_tabelas.pop_back();
                 $$.traducao = limpeza;
             } 
             ;

BLOCO        : BLOCO_INICIO COMANDOS BLOCO_FIM  {$$.traducao = $2.traducao + $3.traducao; }
             | BLOCO_INICIO BLOCO_FIM {$$.traducao = $2.traducao; }
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
            | LARRAY '=' E ';'
            {
                if ($3.tipo == "string")
                    yyerror("Nao e possivel armazenar strings em arrays.");
                string conv = "";
                string lf = converter($3.tipo, $1.tipo, $3.label, conv);
                if (lf == "ERRO_TIPO")
                    yyerror("Tipo incompativel na atribuicao ao array '" + $1.arr_id + "'.");
                $$.traducao = $1.traducao + $3.traducao + conv +
                              "\t" + $1.arr_temp + "[" + $1.label + "] = " + lf + ";\n";
            }
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
            | FOR '(' FOR_INIT ';' OPT_E ';' OPT_ATRIB_FOR ')'
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
                    if ($3.tipo != "string") {
                        yyerror("Tipos incompativeis: esperado uma string.");
                    }
                    $$.traducao = atribuir_string(var.temp, $3);
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
            | TK_ID INC ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | INC TK_ID ';'
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | TK_ID DEC ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | DEC TK_ID ';'
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | TK_ID PLUS_EQ E ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "bool") yyerror("Operador += nao suportado para bool.");
                if(var.tipo == "string") {
                    if($3.tipo != "string") yyerror("Concatenacao += exige duas strings.");
                    string t_new = gentempcode("string");
                    string cod = $3.traducao;
                    cod += "\t" + t_new + " = malloc(contar_chars(" + var.temp + ") + contar_chars(" + $3.label + ") + 1);\n";
                    cod += "\tstrcpy(" + t_new + ", " + var.temp + ");\n";
                    cod += "\tstrcat(" + t_new + ", " + $3.label + ");\n";
                    if($3.kind == "temp") cod += "\tfree(" + $3.label + ");\n";
                    cod += "\tif(" + var.temp + ") free(" + var.temp + ");\n";
                    cod += "\t" + var.temp + " = " + t_new + ";\n";
                    $$.traducao = cod;
                } else {
                    string conv = "";
                    string lf = converter($3.tipo, var.tipo, $3.label, conv);
                    if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em +=.");
                    $$.traducao = $3.traducao + conv + "\t" + var.temp + " += " + lf + ";\n";
                }
            }
            | TK_ID MINUS_EQ E ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em -=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " -= " + lf + ";\n";
            }
            | TK_ID MUL_EQ E ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador *= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em *=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " *= " + lf + ";\n";
            }
            | TK_ID DIV_EQ E ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador /= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em /=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " /= " + lf + ";\n";
            }
            | TK_ID MOD_EQ E ';'
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo != "int" && var.tipo != "char")
                    yyerror("Operador %= so suportado para int e char.");
                if($3.tipo != "int" && $3.tipo != "char")
                    yyerror("Operador %= exige int ou char no lado direito.");
                $$.traducao = $3.traducao + "\t" + var.temp + " %= " + $3.label + ";\n";
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
                string liberar = ($3.tipo == "string" && $3.kind == "temp")
                                  ? ("\tfree(" + $3.label + ");\n") : "";

                $$.traducao = $1.traducao + $3.traducao +
                              gerar_printf($3.tipo, $3.label) +
                              liberar;
            }
            | E
            {
                string liberar = ($1.tipo == "string" && $1.kind == "temp")
                                  ? ("\tfree(" + $1.label + ");\n") : "";

                $$.traducao = $1.traducao +
                              gerar_printf($1.tipo, $1.label) +
                              liberar;
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
                
                string leitura;
                if (var.tipo == "string") {
                    // Strings sao char*. Libera o buffer antigo (se houver) e aloca
                    // um novo para receber a leitura -- sem isso, scanf escreveria
                    // num ponteiro NULL na primeira leitura.
                    leitura = "\tif(" + var.temp + ") free(" + var.temp + ");\n" +
                              "\t" + var.temp + " = malloc(1024);\n" +
                              "\tscanf(\"%s\", " + var.temp + ");\n";
                } else {
                    string formato = obter_formatador(var.tipo);
                    if(var.tipo == "char")
                        leitura = "\tscanf(\" " + formato + "\", &" + var.temp + ");\n";
                    else
                        leitura = "\tscanf(\"" + formato + "\", &" + var.temp + ");\n";
                }
                
                $$.traducao = $1.traducao + leitura;
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
                
                if (var.tipo == "string") {
                    $$.traducao = "\tif(" + var.temp + ") free(" + var.temp + ");\n" +
                                  "\t" + var.temp + " = malloc(1024);\n" +
                                  "\tscanf(\"%s\", " + var.temp + ");\n";
                } else {
                    string formato = obter_formatador(var.tipo);
                    if(var.tipo == "char")
                        $$.traducao = "\tscanf(\" " + formato + "\", &" + var.temp + ");\n";
                    else
                        $$.traducao = "\tscanf(\"" + formato + "\", &" + var.temp + ");\n";
                }
            }
            ;
CASOS   :   LISTA_CASES
            {
                $$.traducao = $1.traducao;
            }

            | LISTA_CASES DEFAULT ':' COMANDOS
            {
                $$.traducao = $1.traducao + $4.traducao;
            }
            ;
ATRIB_FOR   : TK_ID '=' E
            {
                if(!declarada($1.label)) {
                    inserir_simbolo($1.label, $3.tipo, "");
                }
                Simbolo var = obter_simbolo($1.label);
                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }
                if(var.tipo == "string") {
                    if ($3.tipo != "string") yyerror("Tipos incompativeis: esperado uma string.");
                    $$.traducao = atribuir_string(var.temp, $3);
                } else {
                    $$.traducao = $3.traducao + "\t" + var.temp + " = " + $3.label + ";\n";
                }
            }
            | TK_ID INC
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | INC TK_ID
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | TK_ID DEC
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | DEC TK_ID
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                $$.traducao = "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | TK_ID PLUS_EQ E
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "bool") yyerror("Operador += nao suportado para bool.");
                if(var.tipo == "string") {
                    if($3.tipo != "string") yyerror("Concatenacao += exige duas strings.");
                    string t_new = gentempcode("string");
                    string cod = $3.traducao;
                    cod += "\t" + t_new + " = malloc(contar_chars(" + var.temp + ") + contar_chars(" + $3.label + ") + 1);\n";
                    cod += "\tstrcpy(" + t_new + ", " + var.temp + ");\n";
                    cod += "\tstrcat(" + t_new + ", " + $3.label + ");\n";
                    if($3.kind == "temp") cod += "\tfree(" + $3.label + ");\n";
                    cod += "\tif(" + var.temp + ") free(" + var.temp + ");\n";
                    cod += "\t" + var.temp + " = " + t_new + ";\n";
                    $$.traducao = cod;
                } else {
                    string conv = "";
                    string lf = converter($3.tipo, var.tipo, $3.label, conv);
                    if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em +=.");
                    $$.traducao = $3.traducao + conv + "\t" + var.temp + " += " + lf + ";\n";
                }
            }
            | TK_ID MINUS_EQ E
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool") yyerror("Operador -= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em -=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " -= " + lf + ";\n";
            }
            | TK_ID MUL_EQ E
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool") yyerror("Operador *= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em *=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " *= " + lf + ";\n";
            }
            | TK_ID DIV_EQ E
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool") yyerror("Operador /= nao suportado para o tipo " + var.tipo + ".");
                string conv = "";
                string lf = converter($3.tipo, var.tipo, $3.label, conv);
                if(lf == "ERRO_TIPO") yyerror("Tipos incompativeis em /=.");
                $$.traducao = $3.traducao + conv + "\t" + var.temp + " /= " + lf + ";\n";
            }
            | TK_ID MOD_EQ E
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo != "int" && var.tipo != "char") yyerror("Operador %= so suportado para int e char.");
                if($3.tipo != "int" && $3.tipo != "char") yyerror("Operador %= exige int ou char no lado direito.");
                $$.traducao = $3.traducao + "\t" + var.temp + " %= " + $3.label + ";\n";
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

/* For init */
FOR_INIT    : ATRIB_FOR     { $$.traducao = $1.traducao; }
            | DECL           { $$.traducao = $1.traducao; }
            |                { $$.traducao = ""; }
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

LISTA_CASES: CASO_NORMAL LISTA_CASES
            {
                $$.traducao = $1.traducao + $2.traducao;
            }

            | CASO_NORMAL
            {
                $$.traducao = $1.traducao;
            }
            ;
CASO_NORMAL:CASE E ':' COMANDOS
              {
                  // Resgata quem eh o switch alvo
                string var_label = switch_expr_stack.back();
                string var_tipo = switch_tipo_stack.back();
                string l_fim = stack_fim.back();
                string l_next = gen_label(); // Se errar esse case, pula pro proximo
                string temp_cond = gentempcode("bool");

                if (var_tipo == "string" || $2.tipo == "string") {
                    yyerror("O switch ainda nao suporta comparacao de strings.");
                }
                  if(var_tipo != $2.tipo)
                {
                    yyerror("Tipo do case incompatível com o tipo do switch.");
                }

                  // Monta o "if" desse caso
                  $$.traducao = $2.traducao +
                                "\t" + temp_cond + " = " + var_label + " == " + $2.label + ";\n" +
                                "\tif(!" + temp_cond + ") goto " + l_next + ";\n" +
                                $4.traducao +
                                "\tgoto " + l_fim + ";\n" + // Break automatico no fim do case
                                "\t" + l_next + ":\n";
              }
            ;


DECL        : TIPO TK_ID
            {
                if(declarada_no_escopo_atual($2.label))
                    yyerror("Variavel ja declarada neste escopo");
                inserir_simbolo($2.label, $1.tipo, "");
                $$.traducao = "";
            }
            | TIPO TK_ID '=' E
            {
                if(declarada_no_escopo_atual($2.label))
                    yyerror("Variavel ja declarada neste escopo");
                string tipo_id = $1.tipo;
                string temp_id = gentempcode(tipo_id);
                inserir_simbolo($2.label, tipo_id, temp_id);
                if(tipo_id == "string") {
                    if ($4.tipo != "string") yyerror("Tipos incompativeis: esperado uma string.");
                    $$.traducao = atribuir_string(temp_id, $4);
                } else {
                    string conversoes = "";
                    string label_final = converter($4.tipo, tipo_id, $4.label, conversoes);
                    if (label_final == "ERRO_TIPO") yyerror("Tipos incompativeis: nao e possivel converter para bool.");
                    $$.traducao = $4.traducao + conversoes + "\t" + temp_id + " = " + label_final + ";\n";
                }
            }
            | TIPO TK_ID DIMS
            {
                if (declarada_no_escopo_atual($2.label))
                    yyerror("Variavel ja declarada neste escopo: " + $2.label);
                if ($1.tipo == "string")
                    yyerror("Arrays de string nao sao suportados.");
                int total = 1;
                for (int d : $3.dims) total *= d;
                string arr_temp = gentemparray($1.tipo, total);
                inserir_simbolo_array($2.label, $1.tipo, arr_temp, $3.dims);
                $$.traducao = "";
            }
            | TIPO TK_ID DIMS '=' '{' INIT_OUTER '}'
            {
                if (declarada_no_escopo_atual($2.label))
                    yyerror("Variavel ja declarada neste escopo: " + $2.label);
                if ($1.tipo == "string")
                    yyerror("Arrays de string nao sao suportados.");

                int total = 1;
                for (int d : $3.dims) total *= d;

                string arr_temp = gentemparray($1.tipo, total);
                inserir_simbolo_array($2.label, $1.tipo, arr_temp, $3.dims);

                string cod  = "";
                string zero = ($1.tipo == "float") ? "0.0" : "0";

                if ($6.kind == "flat") {
                    int idx = 0;
                    for (auto &elem : g_init_matrix[0]) {
                        if (idx >= total) yyerror("Inicializador tem mais elementos que o array.");
                        string conv = "";
                        string lf = converter(elem.tipo, $1.tipo, elem.label, conv);
                        if (lf == "ERRO_TIPO") yyerror("Tipo incompativel no inicializador do array.");
                        cod += elem.code + conv +
                               "\t" + arr_temp + "[" + to_string(idx++) + "] = " + lf + ";\n";
                    }
                    for (; idx < total; idx++)
                        cod += "\t" + arr_temp + "[" + to_string(idx) + "] = " + zero + ";\n";
                } else {
                    if ($3.dims.size() < 2)
                        yyerror("Inicializacao aninhada requer array multidimensional.");
                    int ncols = $3.dims.back();
                    int nrows = total / ncols;
                    int ri = 0;
                    for (auto &row : g_init_matrix) {
                        if (ri >= nrows) yyerror("Inicializador tem mais linhas que o array.");
                        int base = ri * ncols, ci = 0;
                        for (auto &elem : row) {
                            if (ci >= ncols) yyerror("Linha " + to_string(ri) + " do inicializador tem mais elementos que colunas.");
                            string conv = "";
                            string lf = converter(elem.tipo, $1.tipo, elem.label, conv);
                            if (lf == "ERRO_TIPO") yyerror("Tipo incompativel no inicializador do array.");
                            cod += elem.code + conv +
                                   "\t" + arr_temp + "[" + to_string(base + ci++) + "] = " + lf + ";\n";
                        }
                        for (; ci < ncols; ci++)
                            cod += "\t" + arr_temp + "[" + to_string(ri * ncols + ci) + "] = " + zero + ";\n";
                        ri++;
                    }
                    for (; ri < nrows; ri++) {
                        int base = ri * ncols;
                        for (int ci = 0; ci < ncols; ci++)
                            cod += "\t" + arr_temp + "[" + to_string(base + ci) + "] = " + zero + ";\n";
                    }
                }
                $$.traducao = cod;
            }
            ;

TIPO        : INT {$$.tipo = "int";}
            | FLOAT_TYPE{ $$.tipo = "float";}
            | CHAR {$$.tipo = "char";}
            | BOOL_TYPE {$$.tipo = "bool";}
            | STRING {$$.tipo = "string";}
            ;
/* Dimensoes */
DIMS        : '[' TK_NUM ']'
            { $$.dims = { stoi($2.label) }; $$.traducao = ""; }
            | DIMS '[' TK_NUM ']'
            { $$.dims = $1.dims; $$.dims.push_back(stoi($3.label)); $$.traducao = ""; }
            ;
/* Elist */
ELIST       : TK_ID '[' E
            {
                if (!declarada($1.label))
                    yyerror("Variavel nao declarada: " + $1.label);
                Simbolo arr = obter_simbolo($1.label);
                if (arr.dims.empty())
                    yyerror("'" + $1.label + "' nao e um array.");
                $$.arr_id   = $1.label;
                $$.arr_temp = arr.temp;
                $$.ndim     = 1;
                $$.tipo     = arr.tipo;
                $$.label    = $3.label;
                $$.traducao = $3.traducao;
            }
            | ELIST ']' '[' E
            {
                int m = $1.ndim + 1;
                Simbolo arr = obter_simbolo($1.arr_id);
                if (m > (int)arr.dims.size())
                    yyerror("Indices em excesso para o array '" + $1.arr_id + "'.");
                int lim = arr.dims[m - 1];
                string t_mul = gentempcode("int");
                string t_add = gentempcode("int");
                $$.arr_id   = $1.arr_id;
                $$.arr_temp = $1.arr_temp;
                $$.ndim     = m;
                $$.tipo     = $1.tipo;
                $$.label    = t_add;
                $$.traducao = $1.traducao + $4.traducao +
                              "\t" + t_mul + " = " + $1.label + " * " + to_string(lim) + ";\n" +
                              "\t" + t_add + " = " + t_mul + " + " + $4.label + ";\n";
            }
            ;

LARRAY      : ELIST ']'
            {
                Simbolo arr = obter_simbolo($1.arr_id);
                if ($1.ndim != (int)arr.dims.size())
                    yyerror("Numero incorreto de indices para '" + $1.arr_id +
                            "': esperado " + to_string(arr.dims.size()) +
                            ", recebido "  + to_string($1.ndim) + ".");
                $$.arr_id   = $1.arr_id;
                $$.arr_temp = $1.arr_temp;
                $$.label    = $1.label;
                $$.tipo     = $1.tipo;
                $$.traducao = $1.traducao;
                $$.kind     = "array_lval";
            }
            ;

/* Inicializadores de array */

FLAT_LIST   : E
            {
                g_init_matrix.clear();
                g_init_matrix.push_back({});
                g_init_matrix.back().push_back({$1.label, $1.traducao, $1.tipo});
                $$.label = "1";
            }
            | FLAT_LIST ',' E
            {
                g_init_matrix.back().push_back({$3.label, $3.traducao, $3.tipo});
                $$.label = to_string(stoi($1.label) + 1);
            }
            ;

ROW_LIST    : E
            {
                g_init_matrix.back().push_back({$1.label, $1.traducao, $1.tipo});
                $$.label = "1";
            }
            | ROW_LIST ',' E
            {
                g_init_matrix.back().push_back({$3.label, $3.traducao, $3.tipo});
                $$.label = to_string(stoi($1.label) + 1);
            }
            ;

INIT_NESTED_START : { g_init_matrix.clear(); } ;
NEW_ROW           :{ g_init_matrix.push_back({}); } ;

NESTED_LIST : INIT_NESTED_START '{' NEW_ROW ROW_LIST '}'
            { $$.label = "1"; $$.kind = "nested"; }
            | NESTED_LIST ',' '{' NEW_ROW ROW_LIST '}'
            { $$.label = to_string(stoi($1.label) + 1); $$.kind = "nested"; }
            ;

INIT_OUTER  : FLAT_LIST   { $$.kind = "flat";   $$.label = $1.label; }
            | NESTED_LIST  { $$.kind = "nested"; $$.label = $1.label; }
            ;
E           : E '+' E    
            {
                if($1.tipo == "string" && $3.tipo == "string"){
                    $$.tipo = "string";
                    $$.kind = "temp"; // resultado eh um buffer novo, ninguem mais eh dono dele ainda
                    $$.label = gentempcode("string");

                    string cod = $1.traducao + $3.traducao;

                    // Um malloc do tamanho exato (sem strlen: usa contar_chars) +
                    // um strcpy + um strcat. Sem buffers desperdicados.
                    cod += "\t" + $$.label + " = malloc(contar_chars(" + $1.label +
                           ") + contar_chars(" + $3.label + ") + 1);\n";
                    cod += "\tstrcpy(" + $$.label + ", " + $1.label + ");\n";
                    cod += "\tstrcat(" + $$.label + ", " + $3.label + ");\n";

                    // Operandos que eram temporarios intermediarios (ex.: em "a+b+c",
                    // o resultado de "a+b") nao sao mais necessarios -> libera aqui,
                    // senao concatenacoes encadeadas vazam memoria a cada "+".
                    if ($1.kind == "temp") cod += "\tfree(" + $1.label + ");\n";
                    if ($3.kind == "temp") cod += "\tfree(" + $3.label + ");\n";

                    $$.traducao = cod;
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
                if ($2.tipo == "string" || $4.tipo == "string") {
                    yyerror("Cast envolvendo strings nao e suportado.");
                }

                string temp_copia = gentempcode($4.tipo);
                string temp_cast  = gentempcode($2.tipo);
                $$.tipo  = $2.tipo;
                $$.label = temp_cast;
                
                // Impede que o C receba um bool
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
                $$.kind = $2.kind;
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
                $$.kind = "lit"; // literal estatico
                $$.label = $1.label;
                $$.traducao = "";
            }
            | TK_ID
            {
                if(!declarada($1.label))
                {
                    yyerror("Variavel nao declarada: " + $1.label);
                }

                Simbolo var = obter_simbolo($1.label);

                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                $$.tipo = var.tipo;
                $$.label = var.temp;
                $$.kind = (var.tipo == "string") ? "var" : "";
                $$.traducao = "";
            }
            | '-' E %prec UMINUS
            {
                if($2.tipo == "string" || $2.tipo == "bool")
                    yyerror("Operador unario - nao suportado para o tipo " + $2.tipo + ".");
                $$.tipo = $2.tipo;
                $$.label = gentempcode($2.tipo);
                $$.traducao = $2.traducao + "\t" + $$.label + " = -" + $2.label + ";\n";
            }
            | '+' E %prec UPLUS
            {
                if($2.tipo == "string" || $2.tipo == "bool")
                    yyerror("Operador unario + nao suportado para o tipo " + $2.tipo + ".");
                $$.tipo = $2.tipo;
                $$.label = $2.label;
                $$.traducao = $2.traducao;
            }
            | INC TK_ID
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                $$.tipo = var.tipo;
                $$.label = var.temp;
                $$.traducao = "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | DEC TK_ID
            {
                if(!declarada($2.label)) yyerror("Variavel nao declarada: " + $2.label);
                Simbolo var = obter_simbolo($2.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                $$.tipo = var.tipo;
                $$.label = var.temp;
                $$.traducao = "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | TK_ID INC
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador ++ nao suportado para o tipo " + var.tipo + ".");
                string t_old = gentempcode(var.tipo);
                $$.tipo = var.tipo;
                $$.label = t_old;
                $$.traducao = "\t" + t_old + " = " + var.temp + ";\n"
                            + "\t" + var.temp + " = " + var.temp + " + 1;\n";
            }
            | TK_ID DEC
            {
                if(!declarada($1.label)) yyerror("Variavel nao declarada: " + $1.label);
                Simbolo var = obter_simbolo($1.label);
                if(var.tipo == "string" || var.tipo == "bool")
                    yyerror("Operador -- nao suportado para o tipo " + var.tipo + ".");
                string t_old = gentempcode(var.tipo);
                $$.tipo = var.tipo;
                $$.label = t_old;
                $$.traducao = "\t" + t_old + " = " + var.temp + ";\n"
                            + "\t" + var.temp + " = " + var.temp + " - 1;\n";
            }
            | LARRAY
            {
                string t = gentempcode($1.tipo);
                $$.tipo     = $1.tipo;
                $$.label    = t;
                $$.kind     = "";
                $$.traducao = $1.traducao +
                              "\t" + t + " = " + $1.arr_temp + "[" + $1.label + "];\n";
            }
            ;

%%

#include "lex.yy.c"

int yyparse();

string declaraTemp(){
    string s;

    for (auto &t : temporarios) {
        if (t.array_size > 0) {
            string ctype = (t.tipo == "bool") ? "int" : t.tipo;
            s += "\t" + ctype + " " + t.nome + "[" + to_string(t.array_size) + "] = {0};\n";
        } else if(t.tipo == "string"){
            s += "\tchar* " + t.nome + " = NULL;\n";
        } else if(t.tipo == "bool"){
            s += "\tint " + t.nome + ";\n";
        } else {
            s += "\t" + t.tipo + " " + t.nome + ";\n";
        }
    }

    return s;
}

string gentempcode(string tipo)
{
    var_temp_qnt++;
    string nome = "t" + to_string(var_temp_qnt);
    temporarios.push_back({nome, tipo, 0});
    return nome;
}

string gentemparray(string tipo, int size)
{
    var_temp_qnt++;
    string nome = "t" + to_string(var_temp_qnt);
    temporarios.push_back({nome, tipo, size});
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