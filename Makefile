# Do not let mess "cd" with user-defined paths.
CDPATH:=

test: testnvim testvim

VADER?=Vader!
VIM_ARGS='+$(VADER) tests/*.vader'

export TESTS_VADER_DIR:=$(firstword $(wildcard tests/vim/plugins/vader.override) tests/vim/plugins/vader)
$(TESTS_VADER_DIR):
	mkdir -p $(dir $@)
	git clone --depth=1 https://github.com/junegunn/vader.vim $@

TEST_VIMRC:=tests/vim/vimrc

testnvim: TEST_VIM:=VADER_OUTPUT_FILE=/dev/stderr nvim
testnvim: $(TESTS_VADER_DIR)
testnvim: build/neovim-test-home
	@# Neovim needs a valid HOME (https://github.com/neovim/neovim/issues/5277).
	HOME=build/neovim-test-home $(TEST_VIM) -nNu $(TEST_VIMRC) -i NONE $(VIM_ARGS) >/dev/null
	
testvim: TEST_VIM:=vim -X
testvim: $(TESTS_VADER_DIR)
testvim:
	HOME=/dev/null $(TEST_VIM) -nNu $(TEST_VIMRC) -i NONE $(VIM_ARGS) >/dev/null

# Interactive tests, keep Vader open.
testinteractive: VADER:=Vader
testinteractive: testvim

testninteractive: VADER:=Vader
testninteractive: TEST_VIM:=VADER_OUTPUT_FILE=/dev/stderr nvim
testninteractive: _run_tests

# Manually invoke Vim, using the test setup.  This helps with building tests.
runvim: VIM_ARGS:=
runvim: testinteractive

runnvim: VIM_ARGS:=
runnvim: testninteractive

TEST_TARGET:=test

# Add targets for .vader files, absolute and relative.
# This can be used with `b:dispatch = ':Make %'` in Vim.
TESTS:=$(filter-out tests/_%.vader,$(wildcard tests/*.vader))
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))
_TESTS_REL_AND_ABS:=$(call uniq,$(abspath $(TESTS)) $(TESTS))
$(_TESTS_REL_AND_ABS):
	make $(TEST_TARGET) VIM_ARGS='+$(VADER) $@'
.PHONY: $(_TESTS_REL_AND_ABS)

tags:
	ctags -R --langmap=vim:+.vader

# Linters, called from .travis.yml.
vint:
	vint .
vint-errors:
	vint --error .
vimlint:
	sh /tmp/vimlint/bin/vimlint.sh -l /tmp/vimlint -p /tmp/vimlparser .
vimlint-errors:
	sh /tmp/vimlint/bin/vimlint.sh -E -l /tmp/vimlint -p /tmp/vimlparser .

build build/neovim-test-home:
	mkdir $@
build/neovim-test-home: | build
build/vim-vimhelplint-master: | build
	cd build \
	&& wget -O- https://github.com/machakann/vim-vimhelplint/archive/master.tar.gz \
	  | tar xz
vimhelplint: VIMHELPLINT_VIM:=vim
vimhelplint: | build/vim-vimhelplint-master
	out="$$($(VIMHELPLINT_VIM) -esN -c 'e doc/neomake.txt' -c 'set ft=help' \
	  -c 'source build/vim-vimhelplint-master/ftplugin/help_lint.vim' \
	  -c 'verb VimhelpLintEcho' -c q 2>&1)"; \
	  if [ -n "$$out" ]; then \
	    echo "$$out"; \
	    exit 1; \
	  fi

docker_vimhelplint:
	$(MAKE) docker_make "DOCKER_MAKE_TARGET=vimhelplint \
	  VIMHELPLINT_VIM=/vim-build/bin/vim-master"

docker_make: DOCKER_RUN:=make -C /testplugin $(DOCKER_MAKE_TARGET)
docker_make: docker_run

# Run tests in dockerized Vims.
DOCKER_IMAGE:=neomake/vims-for-tests
DOCKER_STREAMS:=-ti
DOCKER=docker run $(DOCKER_STREAMS) --rm \
       -v $(PWD):/testplugin -v $(PWD)/tests/vim:/home $(DOCKER_IMAGE)
docker_image:
	docker build -f Dockerfile.tests -t $(DOCKER_IMAGE) .
docker_push:
	docker push $(DOCKER_IMAGE)

DOCKER_VIMS:=vim73 vim74-trusty vim74-xenial vim8000 vim-master
_DOCKER_VIM_TARGETS:=$(addprefix docker_test-,$(DOCKER_VIMS))

docker_test_all: $(_DOCKER_VIM_TARGETS)

$(_DOCKER_VIM_TARGETS):
	$(MAKE) docker_test DOCKER_VIM=$(patsubst docker_test-%,%,$@)

docker_test: DOCKER_VIM:=vim-master
docker_test: DOCKER_STREAMS:=-a stderr
docker_test: DOCKER_RUN:=$(DOCKER_VIM) '+$(VADER) tests/*.vader'
docker_test: docker_run

docker_run: $(TESTS_VADER_DIR)
docker_run:
	$(DOCKER) $(if $(DOCKER_RUN),$(DOCKER_RUN),bash)

.PHONY: vint vint-errors vimlint vimlint-errors
.PHONY: test testnvim testvim testinteractive runvim runnvim tags _run_tests
