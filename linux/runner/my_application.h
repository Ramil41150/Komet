#ifndef MY_APPLICATION_H
#define MY_APPLICATION_H

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication, my_application, MY, APPLICATION, GtkApplication)

MyApplication *my_application_new();

#endif