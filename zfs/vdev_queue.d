#!/usr/sbin/dtrace -s
#pragma D option bufsize=512K
#pragma D option aggsize=512K

/* from Rick Weisner */

vdev_queue_io_to_issue:return
/arg1 != NULL/
{
        @c["issued I/O"] = count();
}

vdev_queue_io_to_issue:return
/arg1 == NULL/
{
        @c["didn't issue I/O"] = count();
}

vdev_queue_io_to_issue:entry
{
        @avgers["avg pending I/Os"] = avg(args[0]->vq_pending_tree.avl_numnodes);
        @quant["quant pending I/Os"] = quantize(args[0]->vq_pending_tree.avl_numnodes);
        @c["total times tried to issue I/O"] = count();
}

vdev_queue_io_to_issue:entry
/args[0]->vq_pending_tree.avl_numnodes > 256/
{
        @avgers["avg pending I/Os > 256"] = avg(args[0]->vq_pending_tree.avl_numnodes);
        @lquant["quant pending I/Os > 256"] = lquantize(args[0]->vq_pending_tree.avl_numnodes, 33, 1000, 1);
        @c["total times tried to issue I/O where > 256"] = count();
}

tick-1
{
                printf("\n Date: %Y \n", walltimestamp);
                printa(@c);
                printa(@avgers);
                printa(@quant);
                printa(@lquant);
                trunc(@c);
                trunc(@avgers);
                trunc(@quant);
                trunc(@lquant);
} 
/* bail after 5 minutes */
tick-300sec
{
	exit(0);
}
