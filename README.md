# Chapter 22: Introducing OTP

This is one possible implementation of the `job_centre` module outlined in the exercises at the end of Chapter 22 in the book _Programming Erlang_ 2/ed by Joe Armstrong (Pragmatic, 2013). The optional `trade_union` module is also implemented. Both modules were based on the `gen_server_template.full` file, which was taken from the code for the book.

Three `ets` tables are used to hold the state of jobs for the `job_centre` server: available jobs, jobs that are being worked-on, and jobs that are done. Only the `avail` table needs to be an ordered set, and only the `working` table needs to hold pids and timer references. Simple tuples are used to represent the data objects rather than records.
