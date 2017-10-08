## adelbertc.github.io

To publish a new post, make sure the source file is committed and there is no `master` branch. Then run
the `deploy` script.

This will automate everything up until the actual pushing of the commit upstream. You will be dropped
into a `git diff` to verify the changes are what you want. If you're satisfied then:

```
$ git push origin master
$ git checkout develop
$ git branch -D master
$ git stash pop
```
