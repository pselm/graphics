var gulp = require("gulp");
var purescript = require("gulp-purescript");
var fork = require('child_process').fork;
var spawn = require('child_process').spawn;
var exec = require('child_process').exec;

var sources = [
    "src/**/*.purs",
    "bower_components/purescript-*/src/**/*.purs",
    "test/**/*.purs",
    "examples/**/*.purs"
];

var foreigns = [
    "src/**/*.js",
    "bower_components/purescript-*/src/**/*.js",
    "test/**/*.js",
    "examples/**/*.js"
];

// A list of things to process via pscBundle.
//
// `module` is the name of the relevant Purescript module
//
// `purs` is the path to the Purescript source file
//
// `html` is the html page that uses the bundle ... it
//        is left out for bundles where main runs in Node.
//
// We make a gulp task for each bundle that uses pscBundle
// to bundle it, and then either runs it via Node (if no
// `html`), or opens the given `html` page.
//
// The task is given each of the names. So, you can invoke
// it (for instance) via any of these:
//
//     gulp Examples.Graphics.StaticElement
//     gulp examples/Graphics/StaticElement.purs
//     gulp examples/Graphics/StaticElement.html
var bundles = [{
    module: "Examples.Graphics.StaticElement",
    purs: "examples/Graphics/StaticElement.purs",
    html: "examples/Graphics/StaticElement.html"
},{
    module: "Examples.Graphics.UpdateElement",
    purs: "examples/Graphics/UpdateElement.purs",
    html: "examples/Graphics/UpdateElement.html"
},{
    module: "Examples.Graphics.UpdateRandomRenderable",
    purs: "examples/Graphics/UpdateRandomRenderable.purs",
    html: "examples/Graphics/UpdateRandomRenderable.html"
},{
    module: "Examples.Graphics.StaticCollage",
    purs: "examples/Graphics/StaticCollage.purs",
    html: "examples/Graphics/StaticCollage.html"
},{
    module: "Examples.Graphics.UpdateCollage",
    purs: "examples/Graphics/UpdateCollage.purs",
    html: "examples/Graphics/UpdateCollage.html"
},{
    module: "Test.Main",
    purs: "test/Test/Main.purs"
}];

function output (module) {
    return "build/" + module.split(".").join("/") + ".js";
}

bundles.map(function (bundle) {
    var bundleName = "bundle-" + bundle.module;

    gulp.task(bundleName, ["make"], function () {
        return purescript.bundle({
            src: "output/**/*.js",
            output: output(bundle.module),
            module: bundle.module,
            main: bundle.module
        });
    });

    gulp.task(bundle.module, [bundleName], function (cb) {
        if (bundle.html) {
            exec("open " + bundle.html);
            cb();
        } else {
            fork(output(bundle.module)).on('exit', cb);
        }
    });

    if (bundle.purs) gulp.task(bundle.purs, [bundle.module]);
    if (bundle.html) gulp.task(bundle.html, [bundle.module]);
});

gulp.task("bundle", bundles.map(function (bundle) {
    return "bundle-" + bundle.module;
}));

gulp.task("test", ["Test.Main"]);

gulp.task("make", function () {
    return purescript.compile({
        src: sources,
        ffi: foreigns
    });
});

gulp.task("docs", ["make"], function () {
    return purescript.docs({
        src: sources,
        format: "markdown",
        docgen: {
            "DOM.Renderable": "docs/DOM/Renderable.md",
            "Elm.Graphics.Collage": "docs/Elm/Graphics/Collage.md",
            "Elm.Graphics.Element": "docs/Elm/Graphics/Element.md"
        }
    });
});

gulp.task("default", ["bundle", "docs"]);
