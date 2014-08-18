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
    $('#depth_org_1').html($('#org_id1 option:selected').html());
    $('#depth_org_2').html($('#org_id2 option:selected').html());

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

    // track analysis
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

    var selection = {};


    genome1.el.on("coge.genome.added", function(event, genome, type) {

        console.info("coge.genome.added");

        var genomeVal = genome.val();
        var typeVal = type.val();

        // console.log("genome.val()", genomeVal);
        // console.log("type.val()", type.val());

//        selected.push({ genome: genome.val(), featType: type.val() });

        // dsgid and feat_type
        var id = genomeVal + type.val();
        var organism = $("#org_list1").find(":selected").text();
        var genomeElement = $("<em></em>", {text: genome.text()}).html();

        var added = _.find(selected, function(each) { return each.genome == genomeVal; });

        // console.log("added", added);

        // if (! (id in selection) ) {
        if (! added) {
            selected.push({ genome: genomeVal, featType: type.val() });

            // console.log("selected", selected);

            genomes.removeClass("hidden");
            selection[id] = {};
            var row = $("<tr></tr>");
            var name = $("<td></td>", {text: organism}).appendTo(row);
            name.append(genomeElement);

            var attribute = $("<input />", {type:"number", min: 1, max: 100})
                .on("change keydown", function() {
                    selection[id + type.val()].value = +$(this).val();
                });

            var remove = $("<span></span>", {"class": "ui-icon ui-icon-trash"})
                .on("click", function() {
                    row.remove();
                    delete selection[id];
                    selected = _.reject(selected, function(each) { return each.genome == genomeVal; });
                    console.log("genome.val()", genomeVal, "selected", selected);
                });

            row.append($("<td></td>").html(type.val()));
            row.append($("<td></td>").html(attribute));
            row.append($("<td></td>").html(remove));

            genomes.append(row);
        }
    });

    var defer,
        plotData = [],
        fileData = [];

    window.runMulti = function(selected) {

        // FIXME: HARD CODED GENOME SELECTIONS FOR DEV ONLY.
        selected = [{featType: "cds", genome: "7114"}, {featType: "cds", genome: "7113"}];

        // Get pairwise (n choose 2) combinations
        var combinations = collectPairs(selected);

        var funcName = "get_results";

        // Get parameters for each pair of genomes
        var pairParams = combinations.map(function(pair) {
            return getMultiParams(funcName, undefined,
                pair[0].genome, pair[1].genome,
                pair[0].featType, pair[0].featType);
        });

        // This is where all the magic happens.
        // Send the parameters to SynMap.pl and parse the results.
        var requests = pairParams.map(function(params) {
            return getRequest(params).done(parseFile);
        });

        // Turn all the requests into proper Deffered objects
        defer = $.when.apply($, requests);

        defer.done(function() {
            console.info("AJAX requests resolved.");

            var allIds = fileData.reduce(function(prev, curr) {
                return _.union( prev, [curr.reference, curr.source] );
            }, []);

            var xIds = allIds;
            var yIds = allIds;

            var thisPair, found, flipped, thisPlot;

            xIds.forEach(function(xId) {
                yIds.forEach(function(yId) {

                    thisPair = [xId, yId];

                    // Given xId and yId, find associated data
                    found = _.filter(fileData, function(each) {
                        var filePair = [each.reference, each.source];
                        var ret = _.difference(filePair, thisPair).length == 0 && _.difference(thisPair, filePair).length == 0;
                        return(ret);
                    })[0];

                    if (! found) return;

                    // We will know right here if the plot data needs to be flipped
                    flipped = found && found.reference === yId ? true : false;

                    if (flipped) {
                        thisPlot = getPlotData(found.data, yId, xId);
                        thisPlot.layers = flipLayers(thisPlot.layers);
                    } else {
                        thisPlot = getPlotData(found.data, xId, yId);
                    }

                    plotData.push({
                        xId: xId,
                        yId: yId,
                        data: thisPlot
                    });

                    /**
                     * genomesObj is a set with one object for each distinct genome in the MultiDotPlot
                     */
                    if ( ! _.has(genomesObj, thisPlot.xid)) {
                        genomesObj[thisPlot.xid] = {
                            name: thisPlot.xtitle,
                            length: thisPlot.xtotal,
                            chromosomes: thisPlot.xlabels
                        };
                    }
                    if ( ! _.has(genomesObj, thisPlot.yid)) {
                        genomesObj[thisPlot.yid] = {
                            name: thisPlot.ytitle,
                            length: thisPlot.ytotal,
                            chromosomes: thisPlot.ylabels
                        };
                    }
                })
            });

            genomesObj.xIds = xIds;
            genomesObj.yIds = yIds;

            var height = 800;
            var width = 1000;

            $("#results").css("min-height", height + "px").show();

            /**
             * plotData needs to be populated prior to now.
             */
            multidotplot = new MultiDotPlot("results", {
                size: { width: width, height: height },
                genomes: genomesObj,
                fetchDataHandler: fetchHandler,
                style: {
                    position: "relative"
                }
            });

        });
    };

    var sortFunc = inverse(sortBy("name", compareAlphaNumeric));

    var plotBuilder = coge.synmap.PlotBuilder();

    var layerData, layerObjects, data, multidotplot;

    var genomesObj = {};

    function getPlotData(json, xAxis, yAxis) {
        plotBuilder.loadJSON(json); // axisMetric is "nucleotides" by default
        plotBuilder.setChromosomeSort(sortFunc);
        plotBuilder.setXAxis(xAxis);
        plotBuilder.setYAxis(yAxis);

        return(plotBuilder.get());
    }

    function parseFile(json) {
        if (json.error) console.error("Error parsing file:", json.error);

        // Hacky way of getting the reference and source IDs
        layerData = _.values(json.layers)[0].data;
        layerObjects = _.values(layerData)[0];
        var reference = _.keys(layerObjects)[0];
        var source = _.keys(layerObjects[reference])[0];

        fileData.push({
            reference: reference,
            source: source,
            data: json
        });

    }

    var temp;
    var flipLine = function(line) {

        temp = line.x1;
        line.x1 = line.y1;
        line.y1 = temp;

        temp = line.x2;
        line.x2 = line.y2;
        line.y2 = temp;

    };

    var syntenicPairs, lines;
    var flipLayers = function(layers) {

        _.each(layers, function(layer) {
            _.each(layer.lines, function(line) { flipLine(line); });
        });

        return layers;
    };

    /**
     * This function needs to return an array of objects with "lines," "rects," etc.
     * This is called for each plot.
     * "xId" and "yId" will be bound prior to the call.
     */
    var fetchHandler = function(xId, yId) {

        // Given xId and yId, find associated data
        var found = _.filter(plotData, function(each) {
            return each.xId == xId && each.yId == yId;
        })[0];

        if (! found) return([]);

        /**
         * Lines needs to be an array of objects instead of one giant object
         */
        lines = _.values( found.data.layers.syntenic_pairs.lines );

        // TODO: More than just lines
        data = [{ lines: lines }];

        return(data);
    };

    var getRequest = function(paramData) {
        return $.ajax("SynMap.pl", {
            type: 'GET',
            data: paramData,
            dataType: "json"
        });
    };

    var collectPairs = function(selected) {
        var combinations = [];
        selected.forEach(function(a) {
            selected.forEach(function(b) {
                var pair = [a, b];
                var found = _.find(combinations, function(each) {
                    return _.intersection(pair, each).length == 2;
                });
                if (! found) combinations.push([a, b]);
            });
        });
        return(combinations);
    };

    runMulti();
});

var getMultiParams = function(name, regenerate, dsgid1, dsgid2, featType1, featType2) {
    return {
        fname: name,
        tdd: $('#tdd').val(),
        D: $('#D').val(),
        A: $('#A').val(),
        beta: pageObj.beta,
        gm: $('#gm').val(),
        Dm: $('#Dm').val(),
        blast: $('#blast').val(),
//        feat_type1: $('#feat_type1').val(),
//        feat_type2: $('#feat_type2').val(),
//        dsgid1: $('#dsgid1').val(),
//        dsgid2: $('#dsgid2').val(),
        feat_type1: featType1,
        feat_type2: featType2,
        dsgid1: dsgid1,
        dsgid2: dsgid2,
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
};