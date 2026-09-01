# Security

## What Tessera is exposed to

Tessera runs on the machine that starts it. It opens no outbound
connection, keeps no account, writes no telemetry, and stores nothing
between sessions except one browser preference recording the chosen
appearance and whether the walkthrough has been seen.

Two things are worth knowing about that boundary.

The file you load is read into memory by the R session on your own
machine. It is never uploaded. Closing the app ends its life.

The optional language model connection speaks to an address you supply,
which defaults to a local Ollama server at `http://localhost:11434`. If
you point that setting at a remote address, the computed prose from the
reading panel is sent there. Nothing else is, and the network data
itself never is, but the summary text describes the network, so a
remote address is a decision worth making on purpose.

## What the code does about it

The one place a reader's data meets the page is a name, which comes from
the tie list they load. Names are treated as data everywhere they are
shown: they are escaped where they are written into markup, and where a
control needs to carry a name it carries it as an attribute rather than
inside a line of script written around it. The test suite refuses any
source file that writes a value into a line of script, so the rule holds
without anyone having to remember it.

Names given to another program follow the same rule. The model name
handed to the runtime is checked against the shape a model name is
allowed to have, and every call passes its arguments as a list rather
than as a command line, so there is no shell to interpret them.

A saved session is a file, and a file can say anything, so what a
session names is checked against what this app actually has before it is
used.

## Reporting a problem

Open a private security advisory through the repository Security tab, or
open a normal issue if the problem is not sensitive. Please include the
version, what you did, and what you saw.

There is no service to take down and no user data to breach, so a
report here is about the code rather than about an incident. Expect a
first reply within a week.

## What counts

In scope: anything that causes the app to write outside its working
directory, to open a connection the reader did not ask for, to execute
content from a loaded file, or to render an uploaded value as markup
without escaping it.

Out of scope: the R packages the app depends on, which are reported to
their own maintainers, and anything that requires an attacker to already
be running code on the same machine.
