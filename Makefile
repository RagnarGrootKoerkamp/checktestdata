-include config.mk

CXXFLAGS += -DVERSION="\"$(VERSION)\""

COVERAGE_CXXFLAGS = $(CXXFLAGS) -fprofile-arcs -ftest-coverage

TARGETS = checktestdata
CHKOBJS = $(addsuffix $(OBJEXT),libchecktestdata parse lex parsetype)
OBJECTS = $(CHKOBJS)

PARSER_GEN = lex.cc scannerbase.h parse.cc parserbase.h

# Function to parse version number from bisonc++/flexc++ --version and
# add it as a define in generated code. This is used in the header
# files to conditionally include declarations that conflict between
# different versions.
INSERT_VERSION = \
sed -i "/^\/\/ Generated by /a \\\\n\#define $(1) \
`echo $(2) | sed 's/^.* V//;s/\\.//g;s/^0*//'`LL" $@

build: $(TARGETS) $(SUBST_FILES)

# These are build during dist stage, and this is independent of
# whether checktestdata is enabled after configure.
ifeq ($(PARSERGEN_ENABLED),yes)
$(PARSER_GEN): config.mk

lex.cc scannerbase.h: checktestdata.l scanner.h scanner.ih
	flexc++ $<
	$(call INSERT_VERSION,FLEXCPP_VERSION,$(shell flexc++ --version))

parse.cc parserbase.h: checktestdata.y parser.h parser.ih parsetype.hpp
	bisonc++ $<
	$(call INSERT_VERSION,BISONCPP_VERSION,$(shell bisonc++ --version))
endif

checksucc = ./checktestdata $$opts $$prog $$data >/dev/null 2>&1 || \
		{ echo "Running './checktestdata $$opts $$prog $$data' did not succeed..." ; exit 1; }
checkfail = ./checktestdata $$opts $$prog $$data >/dev/null 2>&1 && \
		{ echo "Running './checktestdata $$opts $$prog $$data' did not fail..."    ; exit 1; }

config.mk: config.mk.in
	$(error run ./bootstrap and/or configure to create config.mk)

libchecktestdata.o: config.mk
libchecktestdata.o: $(PARSER_GEN)
libchecktestdata.o: %.o: %.cc %.hpp parser.h

checktestdata: CPPFLAGS += $(BOOST_CPPFLAGS)
checktestdata: LDFLAGS  += $(BOOST_LDFLAGS) $(STATIC_LINK_START) $(LIBGMPXX) $(BOOST_REGEX_LIB) $(STATIC_LINK_END)
checktestdata: LDFLAGS := $(filter-out -pie,$(LDFLAGS))
checktestdata: checktestdata.cc $(CHKOBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

check: checktestdata
	@for i in tests/testprog*.in ; do \
		n=$${i#tests/testprog} ; n=$${n%.in} ; \
		prog=$$i ; \
		for data in tests/testdata$$n.in*  ; do $(checksucc) ; done ; \
		for data in tests/testdata$$n.err* ; do $(checkfail) ; done ; \
		data=tests/testdata$$n.in ; \
		for prog in tests/testprog$$n.err* ; do $(checkfail) ; done ; \
	done || true
# Some additional tests with --whitespace-ok option enabled:
	@opts=-w ; \
	for i in tests/testwsprog*.in ; do \
		n=$${i#tests/testwsprog} ; n=$${n%.in} ; \
		prog=$$i ; \
		for data in tests/testwsdata$$n.in*  ; do $(checksucc) ; done ; \
		for data in tests/testwsdata$$n.err* ; do $(checkfail) ; done ; \
		data=tests/testwsdata$$n.in ; \
		for prog in tests/testwsprog$$n.err* ; do $(checkfail) ; done ; \
	done || true
# A single hardcoded test for the --preset option:
	@opts='-g -p n=10,pi=0.31415E1,foo="\"bar\""' ; \
	prog=tests/testpresetprog.in  ; $(checksucc) ; \
	prog=tests/testpresetprog.err ; $(checkfail) ; \
	true
# Test if generating testdata works and complies with the script:
	@TMP=`mktemp --tmpdir dj_gendata.XXXXXX` || exit 1 ; data=$$TMP ; \
	for i in tests/testprog*.in ; do \
		grep 'IGNORE GENERATE TESTING' $$i >/dev/null && continue ; \
		n=$${i#tests/testprog} ; n=$${n%.in} ; \
		prog=$$i ; \
		for i in seq 10 ; do opts=-g ; $(checksucc) ; opts='' ; $(checksucc) ; done ; \
	done ; \
	rm -f $$TMP

coverage:
	$(MAKE) clean
	$(MAKE) CXXFLAGS='$(COVERAGE_CXXFLAGS)'
	$(MAKE) check
	gcov checktestdata.cc libchecktestdata.cc libchecktestdata.hpp

coverage-clean:
	rm -f *.gcda *.gcno *.gcov coverage*.html

# Requires gcovr >= 3.2
coverage-report: coverage
	gcovr -g -r . --html --html-details -o coverage.html

dist: $(PARSER_GEN)

clean:
	-rm -f $(TARGETS) $(OBJECTS)
# Remove Coverity scan data:
	-rm -rf cov-int checktestdata-scan.tar.xz

distclean: clean coverage-clean
	-rm -f $(PARSER_GEN)

.PHONY: build dist check clean distclean coverage coverage-clean coverage-report
