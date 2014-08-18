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

    $(".options tr:even").addClass("even");
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
        // run_synmap(false, $('#regen_images')[0].checked);
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

        console.info("coge.genome.added");

        var genomeVal = genome.val();

        // These correspond to dsgid and feat_type
        var organism = $("#org_list1").find(":selected").text();
        var genomeElement = $("<em></em>", {text: genome.text()}).html();

        console.log("organism", organism);

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
                    console.log("genome.val()", genomeVal, "selected", selected);
                });

            row.append($("<td></td>").html(type.val()));
            row.append($("<td></td>").html(remove));

            genomes.append(row);
        }
    });

    var plotData = [],
        fileData = [];

    // FIXME: runMulti attached to window for Dev only
    window.runMulti = function runMulti(selected) {

        selected = [{featType: "cds", genome: "7098"}, {featType: "cds", genome: "7101"}, {featType: "cds", genome: "7096"}];

        var allIds = selected.reduce(function(prev, curr) {
            return _.union( prev, curr.genome );
        }, []);

        var genomesObj = {};
        var genomeIds = {};

        genomeIds.x = allIds;
        genomeIds.y = allIds;

        genomesObj.xIds = allIds; // [allIds[0]]; // [allIds[1]];
        genomesObj.yIds = allIds; // [allIds[0]]; // [allIds[0]];

        /** FIXME: #results height issues */
        var height = 800;
        $("#results").css("min-height", height + "px").show();

        var config = {
            genomeIds: genomeIds,
            fetchDataHandler: fetchHandler
        };

        /** Create the MultiDotPlot without any genome data */
        this.multiDot = new MultiDotPlot("results", config);

        this.multiDot.divs.forEach(function(div) {

            function resolveOrNotify(json) {
                if (json && (! json.error)) return $.Deferred().resolve(json);
                return $.Deferred().notify(json);
            }

            function make(json) {
                console.info(div.xId, div.yId, "Making plot.");
                makePlot(json, div, this.multiDot);
            }

            function tryFindFlipped(json) {
                console.info(div.xId, div.yId, "Requesting flipped results");
                return getRequestForPair(div.yId, div.xId, "get_results", selected)
                    .then(resolveOrNotify);
            }

            function scheduleJob(existingRequest) {
                var func;
                if (! existingRequest) {
                    func = function() {
                        console.info(div.xId, div.yId, "No existing job. Scheduling job");
                        return getRequestForPair(div.xId, div.yId, "go", selected)
                            .then(function(r) { return $.Deferred().notify(r); });
                    }
                } else {
                    func = function() {
                        return $.Deferred().notify(existingRequest);
                    }
                }
                return func;
            }

            function waitForJob(requestObject, error) {

                if (error) return $.Deferred().reject("Error checking job status:" + error);

                setTimeout(function() {
                    $.getJSON(requestObject.request)
                        .done(function(r) {
                            console.log(div.xId, div.yId, "Request Link:", requestObject.request, "Status:", r);
                            if (r.status === "Completed" || r.status === "Failed") {
                                requestFile(requestObject);
                            } else {
                                waitForJob(requestObject)
                            }
                        })
                        .fail(function(e) {
                            waitForJob(requestObject, e);
                        })
                }, 2 * 1000);
            }

            function requestFile(existingRequest) {
                console.info(div.xId, div.yId, "Requesting results");

                getRequestForPair(div.xId, div.yId, "get_results", selected)
                    .then(resolveOrNotify, null, null)
                    .then(null, null, tryFindFlipped)
                    .then(null, null, scheduleJob(existingRequest))
                    .then(null, null, waitForJob)
                    .fail(function(error) { console.error(div.xId, div.yId, "Error:", error) })
                    .done(make);
            }

            requestFile();
        });

        lineWidthScaleSlider();
        collapseButton();
    };

    window.runMulti();

    function getRequestForPair(xId, yId, funcName, selected) {
        var xGenome = _.find(selected, function(s) { return s.genome == xId; });
        var yGenome = _.find(selected, function(s) { return s.genome == yId; });

        /** Set up params to be "sent" to SynMap.pl */

        var pairParams = getMultiParams(funcName, undefined,
            xGenome.genome, yGenome.genome,
            1, 1);
        // xGenome.featType, yGenome.featType);

        return $.getJSON("SynMap.pl", pairParams);
    }

    function makePlot(data, div) {
        fileData = parseFile(data);

        var flipped = (fileData.reference === div.yId && fileData.source === div.xId && div.xId !== div.yId);

        var thisPlot = (function() {
            if (flipped) return flipPlot(buildPlotData(fileData.data, div.yId, div.xId));
            return buildPlotData(fileData.data, div.xId, div.yId);
        })();

        /** fetchHandler uses plotData */
        plotData.push({
            xId: div.xId,
            yId: div.yId,
            data: thisPlot
        });

        var plotGenomes = [
            {
                name: thisPlot.xtitle,
                length: thisPlot.xtotal,
                chromosomes: thisPlot.xlabels
            },
            {
                name: thisPlot.ytitle,
                length: thisPlot.ytotal,
                chromosomes: thisPlot.ylabels
            }
        ];

        this.multiDot.makeDotPlot(div.xId, div.yId, plotGenomes);
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

        plotBuilder.loadJSON(json); // axisMetric is "nucleotides" by default
        plotBuilder.setChromosomeSort(sortFunc);
        plotBuilder.setXAxis(xAxis);
        plotBuilder.setYAxis(yAxis);

        return(plotBuilder.get());
    }

    function flipPlot(plotData) {
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

