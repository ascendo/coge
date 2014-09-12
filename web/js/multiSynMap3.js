$(document).ready(function(){
    initialize();

    $.ajaxSetup({
        type: "GET",
        dataType: "json",
        cache: false
    });

    $(".dialog_box").dialog({
        autoOpen: false,
        width: 500
    });

    $("#synmap_dialog").dialog({modal: true});

    templateVars.displayDagchainerSettings();

    if ($('#assemble')[0].checked) {
        $('#assemble_info').toggle();
    }

    $(".options").find("tr:even").addClass("even");
    merge_select_check();
    depth_algo_check();

    $("#pair_info").draggable();
    var tabs = $("#tabs");
    tabs.tabs({selected:0});
    $(".resizable").resizable();
    $('#depth_org_1').html($('#org_id1').find('option:selected').html());
    $('#depth_org_2').html($('#org_id2').find('option:selected').html());

    pageObj.fid1 = templateVars.fid1;
    pageObj.fid2 = templateVars.fid2;
    pageObj.tempdir = templateVars.tempdir;
    pageObj.beta = templateVars.beta;

    var autogo = parseInt(templateVars.autogo);
    if (autogo === 1) {
        run_synmap(autogo, $('#regen_images')[0].checked);
    }

    tabs.removeClass("invisible");

    var selected = [];

    $("#synmap_go").on("click", function() {
        console.log("selected", selected);
        runMulti(selected);
        // ga('send', 'event', 'synmap', 'run');
    });

    var organism1 = new OrganismList("#org_list1");
    var genome1 = new Genomes("#genome1");

    $("#org_name1, #org_desc1").on("keyup search", debounce(function(event) {
        var el = $(event.target);
        var type = el.attr("data-search-type");
        var options = {
            fname: "get_orgs",
            name: $("#org_name1").attr("value"),
            desc: $("#org_desc1").attr("value")
        };

        genome1.setGenomes([]);

        if(!options.name && !options.desc) {
            organism1.setDefault();
        } else {
            var search = new Search();
            search.fetch(options).then(function(data) {
                organism1.setOrganisms(data.organisms);
            });
        }
    }, 250));


    $("#org_list1").on("coge.organism.selected", debounce(function(event, organism) {

        var options = {
            fname: "gen_dsg_menu",
            oid: organism
        };

        var search = new Search();

        search.fetch(options).then(function(data) {
            genome1.setGenomes(data.genomes);
        });
    }, 250));

    var genomes = $("#genomes");

    /**
     * Populate the "selected" array with {featType:, genome:} objects
     */
    genome1.el.on("coge.genome.added", function(event, genome, type) {

        var genomeVal = genome.val();

        var organism = $("#org_list1").find(":selected").text();
        var genomeElement = $("<em></em>", {text: genome.text()}).html();

        var added = _.find(selected, function(each) { return each.genome == genomeVal; });

        if (! added) {
            selected.push({ genome: genomeVal, featType: type.val() });

            genomes.removeClass("hidden");

            var row = $("<tr></tr>");
            var name = $("<td></td>", {text: organism}).appendTo(row);

            name.append(genomeElement);

            /** Attribute selection disabled for now */
            // var attribute = $("<input />", {type:"number", min: 1, max: 100})
            //    .on("change keydown", function() {
            //        selection[id + type.val()].value = +$(this).val();
            //    });

            var remove = $("<span></span>", {"class": "ui-icon ui-icon-trash"})
                .on("click", function() {
                    row.remove();
                    selected = _.reject(selected, function(each) { return each.genome == genomeVal; });
                });

            row.append($("<td></td>").html(type.val()));
            row.append($("<td></td>").html(remove));

            genomes.append(row);
        }
    });

    var plotData = [],
        fileData = [],
        multiDot;

    function addDotPlotSelection(selected) {
        var head = "<thead><tr><th>Genome</th><th>X Axis</th><th>Y Axis</th></tr>";

        var plotSelectTable = $("<table>")
            .append(head).append("<tbody>").insertBefore("#results");

        selected.forEach(function(s) {
            var row = $("<tr>").data(s);
            row.append($("<td>").text(s.genome + "-" + s.featType));
            $("<td>").append(checkBox("x")).appendTo(row);
            $("<td>").append(checkBox("y")).appendTo(row);
            plotSelectTable.append(row);
        });

        function checkBox(clas) { return $("<input>").attr("type", "checkbox").attr("checked", true).addClass(clas) }

        return plotSelectTable;
    }

    runMulti(); // FIXME: DEV ONLY

    function runMulti(selected) {

        /** FIXME: #results height issues */
        var size = { width: 800, height: 500 };
        $("#results").css("min-height", size.height + "px").show();

        // FIXME: DEV ONLY
        selected = [
            {featType: "cds", genome: "7098"},
            {featType: "cds", genome: "7101"},
            {featType: "cds", genome: "7096"}
        ];

        var plotSelectTable = addDotPlotSelection(selected);

        var genomeIds = {x: [], y: []};

        $("<button>").text("Generate MultiDotPlot").insertAfter(plotSelectTable)
            .click(function() {
                genomeIds.x = getCheckedIds("x");
                genomeIds.y = getCheckedIds("y");
                makeMulti(genomeIds, size);
            });

        function getCheckedIds(dim) {
            var r = [];
            plotSelectTable.find("." + dim + ":checked").parents("tr")
                .each(function(i, e) { r.push($(e).data().genome) });
            return r;
        }

    }

    function makeMulti(genomeIds, size) {
        $("#results").empty();

        /** Create the MultiDotPlot without any genome data */
        multiDot = new MultiDotPlot("results")
            .size(size)
            .genomeIds(genomeIds)
            .fetchDataHandler(fetchHandler)
            .axisSizeRatio({x: 0.35, y: 0.25 })
            .build();

        console.groupCollapsed("Fetching Plot Data");

        multiDot.dotPlots().forEach(function(dotplot) {

            var genomeIds = dotplot.genomeIds(),
                findFlippedFunc = tryFindFlipped(genomeIds);

            function requestFile(existingRequest) {
                console.info(genomeIds.x, genomeIds.y, "Requesting results");

                var scheduleJobFunc = scheduleJob(genomeIds, existingRequest);

                getRequestForGenomes(genomeIds.x, genomeIds.y, "get_results", selected)
                    .then(resolveOrCall( findFlippedFunc ))
                    .then(resolveOrCall( scheduleJobFunc ))
                    .then(null, null, waitForJob(requestFile))
                    .then(make(dotplot), function(e) { console.log("Error:", e) });
            }

            requestFile();
        });

        console.groupEnd("Fetching Plot Data");

//        lineWidthScaleSlider();
//        collapseButton();
    }

    function getRequestForGenomes(xId, yId, funcName) {
        /** Set up params to be "sent" to SynMap.pl */
        var pairParams = getMultiParams(funcName, undefined, xId, yId, 1, 1);

        return $.getJSON("SynMap.pl", pairParams);
    }

    function resolveOrCall(func) {
        return function(data) {
            if (data.error) return func(data);
            return data;
        }
    }

    function tryFindFlipped(genomeIds) {
        return function(data) {
            console.info(genomeIds.x, genomeIds.y, "Requesting flipped results");
            return getRequestForGenomes(genomeIds.y, genomeIds.x, "get_results", selected);
        }
    }

    function scheduleJob(genomeIds, existingRequest) {
        if (! existingRequest) {
            return function() {
                console.info(genomeIds.x, genomeIds.y, "No existing job. Scheduling job");
                return getRequestForGenomes(genomeIds.x, genomeIds.y, "go", selected)
                    .then(function(newRequest) { return $.Deferred().notify(newRequest); });
            }
        } else {
            return function() {
                return $.Deferred().notify(existingRequest);
            }
        }
    }

    function waitForJob(requestFileFunc) {
        return function wait(requestObject, error) {
            if (error) return $.Deferred().reject("Error checking job status:" + error);

            setTimeout(function() {
                $.getJSON(requestObject.request)
                    .done(function(r) {
                        console.log("Request Link:", requestObject.request, "Status:", r);
                        if (r.status === "Completed" || r.status === "Failed") {
                            requestFileFunc(requestObject);
                        } else {
                            wait(requestObject)
                        }
                    })
                    .fail(function(e) {
                        wait(requestObject, e);
                    })
            }, 2 * 1000);
        }
    }

    function make(dotplot) {
        return function(json) {
            // console.info(dotplot.xId, dotplot.yId, "Parsing data.");
            var data = parseDataForPlot(json, dotplot);
            plotData.push({
                xId: dotplot.xId,
                yId: dotplot.yId,
                data: data
            });
            dotplot.chromosomes({
                x: data.xlabels, y: data.ylabels
            });
            dotplot.axes()["x"].title(data.xtitle);
            dotplot.axes()["y"].title(data.ytitle);
            dotplot.redraw();
            dotplot.toggleAxes();
            multiDot.positionAll();
        }
    }

    function parseDataForPlot(data, plot) {
        fileData = parseFile(data);

        var flipped = (fileData.reference === plot.yId && fileData.source === plot.xId && plot.xId !== plot.yId);

        if (flipped)
            return flipData(buildPlotData(fileData.data, plot.yId, plot.xId));
        else
            return buildPlotData(fileData.data, plot.xId, plot.yId);
    }

    function parseFile(json) {
        if (json.error)
            console.error("Error parsing file:", json.error);
        // else console.info("JSON parsed successfully.");

        /** Hacky way of getting the reference and source IDs */
        var layerData = _.values(json.layers)[0].data;
        var layerObjects = _.values(layerData)[0];
        var reference = _.keys(layerObjects)[0];
        var source = _.keys(layerObjects[reference])[0];

        return {
            reference: reference,
            source: source,
            data: json
        };
    }

    function buildPlotData(json, xAxis, yAxis) {
        var plotBuilder = coge.synmap.PlotBuilder();
        var sortFunc = inverse(sortBy("name", compareAlphaNumeric));

        plotBuilder.loadJSON(json); /** axisMetric is "nucleotides" by default */
        plotBuilder.setChromosomeSort(sortFunc);
        plotBuilder.setXAxis(xAxis);
        plotBuilder.setYAxis(yAxis);

        return(plotBuilder.get());
    }

    function flipData(plotData) {
        var flipped = {};

        flipped.xid = plotData.yid;
        flipped.yid = plotData.xid;

        flipped.xlabels = plotData.ylabels;
        flipped.ylabels = plotData.xlabels;

        flipped.xtitle = plotData.ytitle;
        flipped.ytitle = plotData.xtitle;

        flipped.xtotal = plotData.ytotal;
        flipped.ytotal = plotData.xtotal;

        flipped.layers = flipLayers(plotData.layers);
        
        return flipped;
    }

    function flipLine(line) {
        var temp;

        temp = line.x1;
        line.x1 = line.y1;
        line.y1 = temp;

        temp = line.x2;
        line.x2 = line.y2;
        line.y2 = temp;
    }

    function flipLayers(layers) {
        _.each(layers, function(layer) {
            _.each(layer.lines, function(line) { flipLine(line); });
        });

        return layers;
    }

    /**
     * This function returns an array of objects with "lines," "rects," etc.
     * This is called for each plot.
     * "xId" and "yId" will be bound prior to the call.
     * Relies on plotData
     */
    function fetchHandler(xId, yId) {

        /** Given xId and yId, find associated data */
        var found = _.filter(plotData, function(each) {
            return each.xId == xId && each.yId == yId;
        })[0];

        // FIXME: When no data is found, returns empty array
        if (! found) return([]);

        if (! found.data.layers.syntenic_pairs) {
            console.error("No syntenic pairs found.");
            console.log("found.data.layers", found.data.layers);
        }

        /** Convert lines from an object to an array of objects */
        var lines = _.values( found.data.layers.syntenic_pairs.lines );

        // TODO: More than just lines
        return [{ lines: lines }];
    }

    function getMultiParams(name, regenerate, dsgid1, dsgid2, featType1, featType2) {
        return {
            fname: name,
            tdd: $('#tdd').val(),
            D: $('#D').val(),
            A: $('#A').val(),
            beta: pageObj.beta,
            gm: $('#gm').val(),
            Dm: $('#Dm').val(),
            blast: $('#blast').val(),
            feat_type1: featType1, // $('#feat_type1').val()
            feat_type2: featType2, // $('#feat_type2').val()
            dsgid1: dsgid1, // $('#dsgid1').val()
            dsgid2: dsgid2, // $('#dsgid2').val()
            jobtitle: $('#jobtitle').val(),
            basename: pageObj.basename,
            email: $('#email').val(),
            regen_images: regenerate,
            width: $('#master_width').val(),
            dagchainer_type: $('#dagchainer_type').filter(':checked').val(),
            ks_type: $('#ks_type').val(),
            assemble: $('#assemble')[0].checked,
            axis_metric: $('#axis_metric').val(),
            axis_relationship: $('#axis_relationship').val(),
            min_chr_size: $('#min_chr_size').val(),
            spa_ref_genome: $('#spa_ref_genome').val(),
            show_non_syn: $('#show_non_syn')[0].checked,
            color_type: $('#color_type').val(),
            box_diags: $('#box_diags')[0].checked,
            merge_algo: $('#merge_algo').val(),
            depth_algo: $('#depth_algo').val(),
            depth_org_1_ratio: $('#depth_org_1_ratio').val(),
            depth_org_2_ratio: $('#depth_org_2_ratio').val(),
            depth_overlap: $('#depth_overlap').val(),
            // fid1: pageObj.fid1,
            // fid2: pageObj.fid2,
            show_non_syn_dots: $('#show_non_syn_dots')[0].checked,
            flip: $('#flip')[0].checked,
            clabel: $('#clabel')[0].checked,
            skip_rand: $('#skiprand')[0].checked,
            color_scheme: $('#color_scheme').val(),
            chr_sort_order: $('#chr_sort_order').val(),
            codeml_min: $('#codeml_min').val(),
            codeml_max: $('#codeml_max').val(),
            logks: $('#logks')[0].checked,
            csco: $('#csco').val(),
            jquery_ajax: 1,
            return_json: 1
        };
    }

    var lineWidthScaleSlider = function() {
        var slider = $("<input>")
            .prop("type", "range")
            .attr({
                id: "lineWidthScale",
                min: 1, max: 10,
                value: 1
            });

        var label = $("<label>")
            .attr("for", slider.attr("id"))
            .text(slider.attr("id"));

        var multiDot = this.multiDot;

        slider.change(function() {
            var scale = this.value;
            multiDot.dotplots.forEach(function(each) {
               each.setLineWidthScale(scale);
               each.redraw();
            });
        });

        $("div").find("#results").prepend(slider).prepend(label);
    };

    var collapseButton = function() {
        var button = $("<button>")
            .prop({
                id: "collapse",
            })
            .text("collapse");

        multiDot = this.multiDot;

        button.click(function() {
            console.log(multiDot);
            multiDot.dotplots.forEach(function(each) {
                return each.xrule = undefined;
            });
            console.log(multiDot);
        });

        $("div").find("#results").prepend(button);
    }

});

