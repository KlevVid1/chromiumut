#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

static Window g_main_window = None;

static Window (*real_XCreateWindow)(Display*, Window, int, int, unsigned int, unsigned int,
                                    unsigned int, int, unsigned int, Visual*,
                                    unsigned long, XSetWindowAttributes*) = NULL;
static Window (*real_XCreateSimpleWindow)(Display*, Window, int, int, unsigned int, unsigned int,
                                          unsigned int, unsigned long, unsigned long) = NULL;
static int (*real_XMapWindow)(Display*, Window) = NULL;
static int (*real_XChangeWindowAttributes)(Display*, Window, unsigned long, XSetWindowAttributes*) = NULL;
static Status (*real_XGetWindowAttributes)(Display*, Window, XWindowAttributes*) = NULL;
static int (*real_XSetTransientForHint)(Display*, Window, Window) = NULL;

static void init_symbols(void) {
    if (!real_XCreateWindow) {
        real_XCreateWindow = dlsym(RTLD_NEXT, "XCreateWindow");
        real_XCreateSimpleWindow = dlsym(RTLD_NEXT, "XCreateSimpleWindow");
        real_XMapWindow = dlsym(RTLD_NEXT, "XMapWindow");
        real_XChangeWindowAttributes = dlsym(RTLD_NEXT, "XChangeWindowAttributes");
        real_XGetWindowAttributes = dlsym(RTLD_NEXT, "XGetWindowAttributes");
        real_XSetTransientForHint = dlsym(RTLD_NEXT, "XSetTransientForHint");
    }
}

static void fix_window_transient(Display *display, Window w, Window parent) {
    if (w == None || !display) return;
    init_symbols();

    Window root = DefaultRootWindow(display);
    if (parent == root || parent == None) {
        if (g_main_window == None) {
            // First normal top-level window created is the main browser window
            if (real_XGetWindowAttributes) {
                XWindowAttributes attr;
                if (real_XGetWindowAttributes(display, w, &attr)) {
                    if (!attr.override_redirect && attr.width > 300 && attr.height > 300) {
                        g_main_window = w;
                    }
                }
            }
        } else if (w != g_main_window) {
            // Popup menu, dropdown, bubble, or tooltip:
            // Explicitly mark it transient for g_main_window so Mir/Xwayland
            // treats it as a child surface instead of a top-level staged window!
            if (real_XSetTransientForHint) {
                real_XSetTransientForHint(display, w, g_main_window);
            }
        }
    }
}

Window XCreateWindow(Display *display, Window parent, int x, int y,
                    unsigned int width, unsigned int height,
                    unsigned int border_width, int depth, unsigned int class,
                    Visual *visual, unsigned long valuemask,
                    XSetWindowAttributes *attributes) {
    init_symbols();
    Window w = real_XCreateWindow ? real_XCreateWindow(display, parent, x, y, width, height,
                                                      border_width, depth, class, visual,
                                                      valuemask, attributes) : None;
    if (w != None && display) {
        int is_override = (valuemask & CWOverrideRedirect) && attributes && attributes->override_redirect;
        Window root = DefaultRootWindow(display);
        if (parent == root) {
            if (!is_override && width > 300 && height > 300 && g_main_window == None) {
                g_main_window = w;
            } else if (g_main_window != None && w != g_main_window) {
                if (real_XSetTransientForHint) {
                    real_XSetTransientForHint(display, w, g_main_window);
                }
            }
        }
    }
    return w;
}

Window XCreateSimpleWindow(Display *display, Window parent, int x, int y,
                          unsigned int width, unsigned int height,
                          unsigned int border_width, unsigned long border,
                          unsigned long background) {
    init_symbols();
    Window w = real_XCreateSimpleWindow ? real_XCreateSimpleWindow(display, parent, x, y, width, height,
                                                                 border_width, border, background) : None;
    if (w != None && display) {
        Window root = DefaultRootWindow(display);
        if (parent == root) {
            if (width > 300 && height > 300 && g_main_window == None) {
                g_main_window = w;
            } else if (g_main_window != None && w != g_main_window) {
                if (real_XSetTransientForHint) {
                    real_XSetTransientForHint(display, w, g_main_window);
                }
            }
        }
    }
    return w;
}

int XChangeWindowAttributes(Display *display, Window w, unsigned long valuemask,
                            XSetWindowAttributes *attributes) {
    init_symbols();
    if ((valuemask & CWOverrideRedirect) && attributes && attributes->override_redirect) {
        if (g_main_window != None && w != g_main_window && real_XSetTransientForHint) {
            real_XSetTransientForHint(display, w, g_main_window);
        }
    }
    return real_XChangeWindowAttributes ? real_XChangeWindowAttributes(display, w, valuemask, attributes) : 0;
}

int XMapWindow(Display *display, Window w) {
    init_symbols();
    fix_window_transient(display, w, DefaultRootWindow(display));
    return real_XMapWindow ? real_XMapWindow(display, w) : 0;
}
