SHELL := /bin/bash
SCANNER := flex
SCANNER_PARAMS := lexico.l
PARSER := bison
PARSER_PARAMS := -d --yacc sintatico.y
CXXFLAGS := -Wno-free-nonheap-object
GCCFLAGS := -Wno-int-conversion -lm
FILE := teste.honor

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
	gcc teste.c $(GCCFLAGS) -o teste
	@echo "./teste"

clean:
	rm -f y.tab.c y.tab.h lex.yy.c glf teste.c teste

run: glf
		./glf < $(FILE) > /tmp/foca_output.c && gcc /tmp/foca_output.c $(GCCFLAGS) -o /tmp/foca_output && /tmp/foca_output

test: glf
	@pass=0; fail=0; \
	for f in exemplos/*.honor; do \
		name=$$(basename $$f .honor); \
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


# test-exec: compila + executa cada .honor e compara saída de runtime com .expected
test-exec: glf
	@pass=0; fail=0; err=0; \
	for f in exemplos/*.honor; do \
		name=$$(basename $$f .honor); \
		expected="exemplos/$$name.expected"; \
		[ -f "$$expected" ] || continue; \
		tmp_c=$$(mktemp /tmp/foca_XXXXXX.c); \
		tmp_e=$$(mktemp /tmp/foca_XXXXXX); \
		if ! ./glf < $$f > $$tmp_c 2>/dev/null; then \
			echo "  ERR  $$name (glf falhou)"; err=$$((err+1)); \
			rm -f $$tmp_c $$tmp_e; continue; \
		fi; \
		if ! gcc $$tmp_c $(GCCFLAGS) -o $$tmp_e 2>/dev/null; then \
			echo "  ERR  $$name (gcc falhou)"; err=$$((err+1)); \
			rm -f $$tmp_c $$tmp_e; continue; \
		fi; \
		if diff -q <($$tmp_e 2>/dev/null) $$expected > /dev/null 2>&1; then \
			echo "  PASS $$name"; pass=$$((pass+1)); \
		else \
			echo "  FAIL $$name"; fail=$$((fail+1)); \
			diff <($$tmp_e 2>/dev/null) $$expected | head -6; \
		fi; \
		rm -f $$tmp_c $$tmp_e; \
	done; \
	echo ""; \
	echo "Resultado: $$pass PASS  $$fail FAIL  $$err ERR"

test-%: glf
	@name=$(patsubst test-%,%,$@); \
	foca=$$(ls exemplos/$${name}_*.honor 2>/dev/null | head -1); \
	if [ -z "$$foca" ]; then \
		echo "Exemplo nao encontrado para etapa $$name"; \
		exit 1; \
	fi; \
	expected=$$(echo $$foca | sed 's/.honor/.expected/'); \
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
