%{
#include <iostream>
#include <string>
#include <vector>
#include <map>

#define YYSTYPE atributos

using namespace std;

int var_temp_qnt;
int label_qnt =0;
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

vector<map<string, Simbolo>> pilha_tabelas(1);

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
                  "int main(void) {\n";
                  
    prog += declaraTemp();
    
    prog += "\n" + traducao_interna + "\treturn 0;\n}\n";
    return prog;
}
%}

%token TK_NUM TK_FLOAT TK_ID TK_CHAR 
%token INT FLOAT_TYPE CHAR DOUBLE BOOL_TYPE
%token IF ELSE FOR WHILE RETURN
%token EQ NE LE GE
%token AND OR TK_BOOL
%token NOT

%start S

%left OR
%left AND
%left EQ NE
%left '<' '>' LE GE
%left '+' '-'
%left '*' '/'
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
            | TIPO TK_ID '=' E ';'
            {
                if(declarada_no_escopo_atual($2.label)) {
                    yyerror("Variavel ja declarada neste escopo");
                }

                string tipo_id = $1.tipo; 
                string temp_id = gentempcode(tipo_id);
                inserir_simbolo($2.label, tipo_id, temp_id);

                string conversoes = "";
                string label_final = converter($4.tipo, tipo_id, $4.label, conversoes);

                if (label_final == "ERRO_TIPO") {
                    yyerror("Tipos incompativeis: nao e possivel converter para bool.");
                }

                $$.traducao = $4.traducao + conversoes +
                              "\t" + temp_id + " = " + label_final + ";\n";
            }
            | TK_ID '=' E ';'
            {
                if(!declarada($1.label)) {
                    yyerror("Variavel nao declarada");
                }
                
                Simbolo var = obter_simbolo($1.label);
                string conversoes = "";
                string label_final = converter($3.tipo, var.tipo, $3.label, conversoes);

                if (label_final == "ERRO_TIPO") {
                    yyerror("Tipos incompativeis: nao e possivel converter para bool.");
                }

                if(var.temp == "") {
                    var.temp = gentempcode(var.tipo);
                    atualizar_temp_simbolo($1.label, var.temp);
                }

                $$.traducao = $3.traducao + conversoes +
                              "\t" + var.temp + " = " + label_final + ";\n";
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

                $$.traducao = $3.traducao +
                              "\t" + var.temp + " = " + $3.label + ";\n";
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
            ;
                        /* Aritmetico */
E           : E '+' E    { $$ = op_aritmetico($1, $3, "+"); }
            | E '-' E    { $$ = op_aritmetico($1, $3, "-"); }
            | E '*' E    { $$ = op_aritmetico($1, $3, "*"); }
            | E '/' E    { $$ = op_aritmetico($1, $3, "/"); }
            /* Relacionais */
            | E '<' E    { $$ = op_relacional($1, $3, "<"); }
            | E '>' E    { $$ = op_relacional($1, $3, ">"); }
            | E LE E     { $$ = op_relacional($1, $3, "<="); }
            | E GE E     { $$ = op_relacional($1, $3, ">="); }
            | E EQ E     { $$ = op_relacional($1, $3, "=="); }
            | E NE E     { $$ = op_relacional($1, $3, "!="); }
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
                $$.traducao = $4.traducao +
                    "\t" + temp_copia + " = " + $4.label + ";\n" +
                    "\t" + temp_cast  + " = (" + $2.tipo + ") " + temp_copia + ";\n";
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
    string decls = "";
    for (auto &t : temporarios) {
        decls += "\t" + t.second + " " + t.first + ";\n";
    }
    return decls;
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