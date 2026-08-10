package utils

// onInterrupt, if set, is invoked once by the process' signal handler before
// it exits due to an interrupt (e.g. Ctrl+C), giving a long-running,
// foreground command a chance to clean up (e.g. unmount a filesystem).
var onInterrupt func()

// OnInterrupt registers f to be run before the process exits due to an
// interrupt signal. Registering a new hook replaces any previously
// registered one.
func OnInterrupt(f func()) {
	onInterrupt = f
}

// RunInterruptHook runs the registered interrupt cleanup hook, if any, and
// is meant to be called by the process' top level signal handler.
func RunInterruptHook() {
	if onInterrupt != nil {
		onInterrupt()
	}
}
