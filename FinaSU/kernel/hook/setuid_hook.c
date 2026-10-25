#include <linux/compiler.h>
#include <linux/version.h>
#include <linux/slab.h>
#include <linux/task_work.h>
#include <linux/thread_info.h>
#include <linux/seccomp.h>
#include <linux/printk.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/uaccess.h>
#include <linux/uidgid.h>
#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#include <linux/workqueue.h>
#include "selinux/selinux.h"
#endif

#include "policy/allowlist.h"
#include "hook/setuid_hook.h"
#include "klog.h" // IWYU pragma: keep
#include "manager/manager_identity.h"
#include "infra/seccomp_cache.h"
#include "supercall/supercall.h"
#include "hook/tp_marker.h"
#include "feature/kernel_umount.h"
#include "feature/uts_view.h"

int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)
{
    (void)suid;

    uid_t new_uid = ruid;
    uid_t old_uid = current_uid().val;

    /* The Android zygote/root transition is the state change we need to track. */
    if (current_user_ns() != &init_user_ns ||
        (!is_zygote(current_cred()) && old_uid != 0)) {
        return 0;
    }

    pr_debug("handle_setresuid from %d to %d\n", old_uid, new_uid);

    if (unlikely(is_uid_manager(new_uid))) {
        spin_lock_irq(&current->sighand->siglock);
        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter)
            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);
        ksu_set_task_tracepoint_flag(current);
        spin_unlock_irq(&current->sighand->siglock);

#ifdef CONFIG_KSU_SUSFS
        task_lock(current);
        current->susfs_task_state &= ~TASK_STRUCT_NON_ROOT_USER_APP_PROC;
        task_unlock(current);
#endif

        pr_info("install fd for manager: %d\n", new_uid);
        ksu_install_fd();
        ksu_uts_view_on_setresuid(old_uid, new_uid);
        return 0;
    }

    if (ksu_is_allow_uid_for_current(new_uid)) {
        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter) {
            spin_lock_irq(&current->sighand->siglock);
            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);
            spin_unlock_irq(&current->sighand->siglock);
        }
        ksu_set_task_tracepoint_flag(current);
#ifdef CONFIG_KSU_SUSFS
        task_lock(current);
        current->susfs_task_state &= ~TASK_STRUCT_NON_ROOT_USER_APP_PROC;
        task_unlock(current);
#endif
    } else {
        ksu_clear_task_tracepoint_flag_if_needed(current);
#ifdef CONFIG_KSU_SUSFS
        task_lock(current);
        if (new_uid >= 10000)
            current->susfs_task_state |= TASK_STRUCT_NON_ROOT_USER_APP_PROC;
        else
            current->susfs_task_state &= ~TASK_STRUCT_NON_ROOT_USER_APP_PROC;
        task_unlock(current);
#endif
    }

    ksu_handle_umount(old_uid, new_uid);
    ksu_uts_view_on_setresuid(old_uid, new_uid);

    return 0;
}

void __init ksu_setuid_hook_init(void)
{
    ksu_kernel_umount_init();
}

void __exit ksu_setuid_hook_exit(void)
{
    pr_info("ksu_core_exit\n");
    ksu_kernel_umount_exit();
}
