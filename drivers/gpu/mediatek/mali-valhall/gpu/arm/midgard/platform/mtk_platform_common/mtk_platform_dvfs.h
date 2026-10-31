/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __MTK_PLATFORM_DVFS_H__
#define __MTK_PLATFORM_DVFS_H__

#include <linux/types.h>
#include <linux/proc_fs.h>
#include <mali_kbase.h>
#include "mtk_gpu_dvfs.h"

int mtk_dvfs_init(struct kbase_device *kbdev);
int mtk_dvfs_term(struct kbase_device *kbdev);
int mtk_dvfs_procfs_init(struct kbase_device *kbdev, struct proc_dir_entry *parent);
int mtk_dvfs_procfs_term(struct kbase_device *kbdev, struct proc_dir_entry *parent);
int kbase_platform_dvfs_event(struct kbase_device *kbdev, u32 utilisation);
void mtk_dvfs_commit_idle(void);
void mtk_dvfs_policy_start(void);
void mtk_dvfs_policy_stop(void);
void mtk_set_gpu_idle_time(unsigned int val);
u64 mtk_common_get_system_timer(void);

#endif /* __MTK_PLATFORM_DVFS_H__ */
