SHELL := /bin/bash
SCANNER := flex
SCANNER_PARAMS := lexico.l
PARSER := bison
PARSER_PARAMS := -d --yacc sintatico.y
CXXFLAGS := -Wno-free-nonheap-object
FILE := teste.foca

all: glf translate

compile: glf

glf: y.tab.c lex.yy.c
		g++ $(CXXFLAGS) -o glf y.tab.c

lex.yy.c: lexico.l
		$(SCANNER) $(SCANNER_PARAMS)

y.tab.c y.tab.h: sintatico.y
		$(PARSER) $(PARSER_PARAMS)

translate: glf
	./glf < $(FILE) > teste.c
	gcc teste.c -Wno-int-conversion -o teste
	@echo "./teste"

clean:
	rm -f y.tab.c y.tab.h lex.yy.c glf teste.c teste

run: glf
		./glf < $(FILE) > /tmp/foca_output.c && gcc /tmp/foca_output.c -o /tmp/foca_output && /tmp/foca_output

test: glf
	@pass=0; fail=0; \
	for f in exemplos/*.foca; do \
		name=$$(basename $$f .foca); \
		expected="exemplos/$$name.expected"; \
		if [ -f "$$expected" ]; then \
			if ./glf < $$f 2>/dev/null | diff -q - $$expected > /dev/null 2>&1; then \
				echo "  PASS: $$name"; \
				pass=$$((pass + 1)); \
			else \
				echo "  FAIL: $$name"; \
				fail=$$((fail + 1)); \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "Resultado: $$pass passou, $$fail falhou"

test-%: glf
	@name=$(patsubst test-%,%,$@); \
	foca=$$(ls exemplos/$${name}_*.foca 2>/dev/null | head -1); \
	if [ -z "$$foca" ]; then \
		echo "Exemplo nao encontrado para etapa $$name"; \
		exit 1; \
	fi; \
	expected=$$(echo $$foca | sed 's/.foca/.expected/'); \
	echo "Entrada: $$foca"; \
	echo "---"; \
	./glf < $$foca; \
	echo "---"; \
	if diff <(./glf < $$foca 2>/dev/null) $$expected > /dev/null 2>&1; then \
		echo "PASS"; \
	else \
		echo "FAIL - Diferenca:"; \
		diff <(./glf < $$foca 2>/dev/null) $$expected; \
	fi