# Compilador FSF

Este repositório contém um compilador desenvolvido para a disciplina de Compiladores.

### Make test

  FAIL: 01_soma<br>
  FAIL: 02_operadores<br>
  PASS: 03_declaracao_temp<br>
  PASS: 04_parenteses<br>
  FAIL: 05_atribuicao<br>
  FAIL: 06_declaracao<br>
  FAIL: 07_float<br>
  PASS: 08_char_bool<br>
  PASS: 09_relacionais<br>
  FAIL: 10_logicos<br>
  FAIL: 11_conversao_implicita<br>
  PASS: 12_conversao_explicita<br>

  #### Erros: 01 e 02
  O exemplo contém erro sintático.

  #### Erros: 05
  O exemplo não contém declaração de variável.
  
  #### Erros: 06
  O exemplo contém expressão sem ponto e vírgula.

  #### Erros: 07
  O resultado difere apenas pela ordem dos fatores, o que não altera o valor devido à comutatividade da multiplicação.

  #### Erros: 10 e 11
  O resultado difere apenas apenas na numeração dos temporários, causada pela ordem de avaliação dos operandos pelo parser, que difere do gabarito.
