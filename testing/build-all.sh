#!/bin/bash
#
# https://stackoverflow.com/a/246128/4804196
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
    DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
    SOURCE=$(readlink "$SOURCE")
    [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

top=$(pwd)/../workdir
libs=$(pwd)/../workdir/libs
apps=$(pwd)/../workdir/apps
uk=$(pwd)/../workdir/unikraft

source "$SCRIPT_DIR"/../include/common_functions

if test $# -lt 1; then
    echo -e "Usage: $0 <PR-number | branch> [deps]\n" 1>&2
    echo "The dependencies are PRs from the unikraft core or external libraries repositories." 1>&2
    echo -e "\ne.g. $0 123 musl/10 unikraft/20 lwip/15" 1>&2
    echo "will pull PRs 123 and 20 from the unikraft core, PR 10 from lib-musl and PR 20 form lwip."
    echo -e "\n$0 staging musl/10 unikraft/20 lwip/15" 1>&2
    echo "will pull PR 20 from the unikraft core, PR 10 from lib-musl and PR 20 form lwip."
    exit 1
fi

log_file=$(pwd)/err.log
PR_number="$1"

unset UK_ROOT UK_WORKDIR UK_LIBS

rm -rf "$top"

setup

pushd "$uk" > /dev/null || exit 1

git checkout staging
git branch -D check-pr-branch 2> /dev/null
if [[ "$1" =~ ^[0-9]+$ ]]; then
	git fetch origin "pull/$PR_number/head":check-pr-branch || exit 1
	git checkout check-pr-branch
	git rebase staging || exit 1
else
	git fetch origin "$1" || exit 1
	git checkout origin/"$1"
fi

popd > /dev/null || exit 1

shift 1
for dep in "$@"; do
	echo $dep
	lib=$(echo "$dep" | cut -d'/' -f1)
	pr=$(echo "$dep" | cut -d'/' -f2)

	if test "$lib" = "unikraft"; then
		pushd "$uk" > /dev/null || exit 1
	else
		pushd "$libs/$lib" > /dev/null || exit 1
	fi

	git checkout setup &> /dev/null || git checkout -b setup &> /dev/null
	git fetch origin "pull/$pr/head":"pr-$pr"
	git rebase "pr-$pr"

	popd > /dev/null || exit 1
done

for script in $(find "../make-based/" -type d -name "app*"); do
	pushd "$script" > /dev/null || exit 1

	app=$(echo "$script" | cut -d'-' -f3-)
	echo -n "Building $app... "
	/bin/bash "do.sh" clean &> /dev/null
	/bin/bash "do.sh" setup &> /dev/null || exit 1
	yes "" | /bin/bash "do.sh" build 1> /dev/null 2> "$log_file.$app" && echo "PASSED" || echo "FAILED"

	popd > /dev/null || exit 1
done
