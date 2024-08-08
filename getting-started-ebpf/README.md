Learn About eBPF

BPF is a revolutionary technology with origins in the Linux kernel that can run sandboxed programs in an operating system kernel. It is used to safely and efficiently extend the capabilities of the kernel without requiring to change kernel source code or load kernel modules.

The JavaScript of the Kernel

eBPF is a kernel technology that allows to dynamically extend the functionalities of the Linux kernel at runtime.

You can think of it as what JavaScript is to the web browser: JavaScript lets you attach callbacks to events in the DOM in order to bring dynamic features to your web page. In a similar fashion, eBPF allows to hook to kernel events and extend their logic when these events are triggered!

Verification and JIT Compilation

Why would eBPF be better than existing solutions to extend the kernel such as kernel modules? 
Besides the fact that it allows an event-driven approach to kernel development, it is also inherently more secure and safe.

That is because eBPF programs are verified when they are injected into the kernel.
