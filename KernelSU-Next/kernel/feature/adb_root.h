#ifndef __KSU_H_ADB_ROOT
#define __KSU_H_ADB_ROOT
#include <asm/ptrace.h>

long ksu_adb_root_handle_execve(struct pt_regs *regs);

bool ksu_adb_root_should_hide_context(const char *context);

void ksu_adb_root_init(void);

void ksu_adb_root_exit(void);

#endif