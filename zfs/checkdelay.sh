#!/bin/bash
dtrace -n fbt::dsl_pool_need_dirty_delay:return'{ @[args[1] == 0 ? "no delay" : "delay"] = count(); }'
